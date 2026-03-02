#!/usr/bin/env python3
"""Concert protocol stress simulator.

This sim models a single conductor and N clients under lossy UDP-like conditions.
It validates handshake lock-in, heartbeat timeout/reacquire behavior, deterministic
cue handling (dedupe + strict sequence ordering), and resend safety.
"""

from __future__ import annotations

import argparse
import heapq
import itertools
import math
import random
import uuid
from dataclasses import dataclass
from typing import Callable, Dict, List, Optional, Tuple


@dataclass(frozen=True)
class ConductorHello:
    protocol_version: int
    show_session_id: str
    expected_device_count: int
    sent_at_ms: int


@dataclass(frozen=True)
class ClientHello:
    slot: int
    device_id: str
    protocol_version: int
    show_session_id: str


@dataclass(frozen=True)
class CueEnvelope:
    slot: int
    protocol_version: int
    show_session_id: str
    seq: int
    cue_id: str
    sent_at_ms: int
    payload: Tuple[object, ...]


@dataclass(frozen=True)
class AckMessage:
    slot: int
    device_id: str
    cue_id: str
    seq: int
    show_session_id: str
    protocol_version: int


@dataclass(frozen=True)
class SimConfig:
    clients: int = 28
    duration_sec: int = 120
    protocol_version: int = 2
    expected_device_count: int = 28
    conductor_hello_interval_ms: int = 1500
    client_hello_interval_ms: int = 2000
    conductor_timeout_ms: int = 8000
    watchdog_tick_ms: int = 1000
    cue_interval_ms: int = 1000
    cue_start_delay_ms: int = 5000
    resend_attempts: int = 3
    resend_spacing_ms: int = 30
    settle_window_ms: int = 2000
    loss_pct: float = 1.0
    jitter_ms: int = 20
    duplication_pct: float = 2.0
    reordering_pct: float = 2.0
    seed: int = 42
    min_ack_ratio: float = 0.95
    min_cues_per_client: int = 1


class SimLoop:
    def __init__(self) -> None:
        self.now_ms = 0
        self._queue: List[Tuple[int, int, Callable[[], None]]] = []
        self._counter = itertools.count()

    def call_later(self, delay_ms: int, callback: Callable[[], None]) -> None:
        when = self.now_ms + max(0, int(delay_ms))
        heapq.heappush(self._queue, (when, next(self._counter), callback))

    def run(self, until_ms: int) -> None:
        while self._queue and self._queue[0][0] <= until_ms:
            when, _, callback = heapq.heappop(self._queue)
            self.now_ms = when
            callback()
        self.now_ms = until_ms


def schedule_periodic(
    loop: SimLoop,
    interval_ms: int,
    until_ms: int,
    callback: Callable[[], None],
    start_delay_ms: int = 0,
) -> None:
    def tick() -> None:
        if loop.now_ms > until_ms:
            return
        callback()
        if loop.now_ms + interval_ms <= until_ms:
            loop.call_later(interval_ms, tick)

    loop.call_later(start_delay_ms, tick)


class ImpairedNetwork:
    def __init__(self, loop: SimLoop, cfg: SimConfig, rng: random.Random) -> None:
        self.loop = loop
        self.cfg = cfg
        self.rng = rng
        self.conductor: Optional[SimConductor] = None
        self.clients: Dict[int, SimClient] = {}

        self.attempted_packets = 0
        self.dropped_packets = 0
        self.injected_duplicates = 0
        self.scheduled_deliveries = 0

    def attach(self, conductor: "SimConductor", clients: Dict[int, "SimClient"]) -> None:
        self.conductor = conductor
        self.clients = clients

    def _schedule_delivery(self, sender: str, recipient: object, packet: object) -> None:
        self.attempted_packets += 1
        if self.rng.random() < (self.cfg.loss_pct / 100.0):
            self.dropped_packets += 1
            return

        delay = 3 + self.rng.randint(0, max(0, self.cfg.jitter_ms))
        if self.rng.random() < (self.cfg.reordering_pct / 100.0):
            # Extra delay increases chance this packet arrives after later packets.
            delay += max(5, self.cfg.jitter_ms + self.rng.randint(0, max(1, self.cfg.jitter_ms * 2)))

        self.scheduled_deliveries += 1
        self.loop.call_later(delay, lambda: recipient.receive(sender, packet))

    def _send_with_impairments(self, sender: str, recipient: object, packet: object) -> None:
        self._schedule_delivery(sender, recipient, packet)
        if self.rng.random() < (self.cfg.duplication_pct / 100.0):
            self.injected_duplicates += 1
            self._schedule_delivery(sender, recipient, packet)

    def conductor_broadcast(self, packet: object) -> None:
        for slot in sorted(self.clients):
            self._send_with_impairments("conductor", self.clients[slot], packet)

    def conductor_unicast(self, slot: int, packet: object) -> None:
        client = self.clients.get(slot)
        if client is None:
            return
        self._send_with_impairments("conductor", client, packet)

    def client_to_conductor(self, slot: int, packet: object) -> None:
        if self.conductor is None:
            return
        self._send_with_impairments(f"client:{slot}", self.conductor, packet)


def _percentile(values: List[float], p: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    index = (len(ordered) - 1) * p
    lo = math.floor(index)
    hi = math.ceil(index)
    if lo == hi:
        return ordered[lo]
    frac = index - lo
    return ordered[lo] * (1.0 - frac) + ordered[hi] * frac


class SimClient:
    cue_id_ttl_ms = 180_000
    max_cue_cache = 4096

    def __init__(self, slot: int, loop: SimLoop, net: ImpairedNetwork, cfg: SimConfig) -> None:
        self.slot = slot
        self.loop = loop
        self.net = net
        self.cfg = cfg

        self.device_id = str(uuid.uuid4())
        self.trusted_sender: Optional[str] = None
        self.locked_show_session_id: Optional[str] = None
        self.last_conductor_heartbeat_ms: Optional[int] = None
        self.last_seq = -1
        self.recent_cue_ids: Dict[str, int] = {}

        self.hellos_sent = 0
        self.hellos_from_conductor = 0
        self.pair_events = 0
        self.unpair_events = 0

        self.cues_processed = 0
        self.acks_sent = 0
        self.duplicates_ignored = 0
        self.out_of_order_dropped = 0
        self.protocol_mismatch_dropped = 0
        self.session_mismatch_dropped = 0
        self.unknown_sender_events = 0

    @property
    def is_paired(self) -> bool:
        return self.trusted_sender is not None and self.locked_show_session_id is not None

    def schedule(self, until_ms: int) -> None:
        schedule_periodic(
            self.loop,
            self.cfg.client_hello_interval_ms,
            until_ms,
            self.send_hello,
            start_delay_ms=self.slot * 5,
        )
        schedule_periodic(
            self.loop,
            self.cfg.watchdog_tick_ms,
            until_ms,
            self.watchdog_tick,
        )

    def watchdog_tick(self) -> None:
        if self.last_conductor_heartbeat_ms is None:
            return
        if self.loop.now_ms - self.last_conductor_heartbeat_ms > self.cfg.conductor_timeout_ms:
            self._unlock("heartbeat timeout")

    def _lock(self, sender: str, show_session_id: str) -> None:
        self.trusted_sender = sender
        self.locked_show_session_id = show_session_id
        self.last_conductor_heartbeat_ms = self.loop.now_ms
        self.last_seq = -1
        self.recent_cue_ids.clear()
        self.pair_events += 1

    def _unlock(self, _reason: str) -> None:
        if self.trusted_sender is not None:
            self.unpair_events += 1
        self.trusted_sender = None
        self.locked_show_session_id = None
        self.last_conductor_heartbeat_ms = None
        self.last_seq = -1
        self.recent_cue_ids.clear()

    def _prune_recent(self) -> None:
        cutoff = self.loop.now_ms - self.cue_id_ttl_ms
        stale = [cue_id for cue_id, seen_at in self.recent_cue_ids.items() if seen_at < cutoff]
        for cue_id in stale:
            self.recent_cue_ids.pop(cue_id, None)

        while len(self.recent_cue_ids) > self.max_cue_cache:
            oldest = next(iter(self.recent_cue_ids))
            self.recent_cue_ids.pop(oldest, None)

    def send_hello(self) -> None:
        msg = ClientHello(
            slot=self.slot,
            device_id=self.device_id,
            protocol_version=self.cfg.protocol_version,
            show_session_id=self.locked_show_session_id or "",
        )
        self.hellos_sent += 1
        self.net.client_to_conductor(self.slot, msg)

    def receive(self, sender: str, packet: object) -> None:
        if isinstance(packet, ConductorHello):
            self._receive_conductor_hello(sender, packet)
            return
        if isinstance(packet, CueEnvelope):
            self._receive_cue(sender, packet)
            return
        self.unknown_sender_events += 1

    def _receive_conductor_hello(self, sender: str, hello: ConductorHello) -> None:
        if sender != "conductor":
            self.unknown_sender_events += 1
            return

        if hello.protocol_version != self.cfg.protocol_version:
            self.protocol_mismatch_dropped += 1
            return

        self.hellos_from_conductor += 1

        if not self.is_paired:
            self._lock(sender, hello.show_session_id)
        elif sender != self.trusted_sender:
            self.unknown_sender_events += 1
            return
        elif hello.show_session_id != self.locked_show_session_id:
            # Trusted conductor started a new show session: relock.
            self._lock(sender, hello.show_session_id)

        self.last_conductor_heartbeat_ms = self.loop.now_ms
        self.send_hello()

    def _receive_cue(self, sender: str, cue: CueEnvelope) -> None:
        if not self.is_paired or sender != self.trusted_sender:
            self.unknown_sender_events += 1
            return

        if cue.protocol_version != self.cfg.protocol_version:
            self.protocol_mismatch_dropped += 1
            return

        if cue.show_session_id != self.locked_show_session_id:
            self.session_mismatch_dropped += 1
            return

        if cue.slot not in (0, self.slot):
            return

        self.last_conductor_heartbeat_ms = self.loop.now_ms

        self._prune_recent()
        if cue.cue_id in self.recent_cue_ids:
            self.duplicates_ignored += 1
            return
        self.recent_cue_ids[cue.cue_id] = self.loop.now_ms

        if self.last_seq >= 0 and cue.seq <= self.last_seq:
            self.out_of_order_dropped += 1
            return

        self.last_seq = cue.seq
        self.cues_processed += 1

        ack = AckMessage(
            slot=self.slot,
            device_id=self.device_id,
            cue_id=cue.cue_id,
            seq=cue.seq,
            show_session_id=self.locked_show_session_id or "",
            protocol_version=self.cfg.protocol_version,
        )
        self.acks_sent += 1
        self.net.client_to_conductor(self.slot, ack)


class SimConductor:
    def __init__(self, loop: SimLoop, net: ImpairedNetwork, cfg: SimConfig) -> None:
        self.loop = loop
        self.net = net
        self.cfg = cfg

        self.show_session_id = str(uuid.uuid4())
        self.next_seq = 1

        self.paired_slots: set[int] = set()
        self.client_protocol_mismatches = 0
        self.client_session_mismatches = 0
        self.unknown_inbound = 0

        self.hellos_sent = 0
        self.hellos_received = 0
        self.cues_generated = 0
        self.acks_received = 0
        self.duplicate_or_late_acks = 0
        self.pending_cues: Dict[Tuple[int, str], int] = {}
        self.ack_latencies_ms: List[float] = []

    def schedule(self, until_ms: int) -> None:
        schedule_periodic(
            self.loop,
            self.cfg.conductor_hello_interval_ms,
            until_ms,
            self.broadcast_hello,
        )
        schedule_periodic(
            self.loop,
            self.cfg.cue_interval_ms,
            until_ms,
            self.send_cue_wave,
            start_delay_ms=self.cfg.cue_start_delay_ms,
        )

    def receive(self, sender: str, packet: object) -> None:
        if isinstance(packet, ClientHello):
            self._receive_client_hello(sender, packet)
            return
        if isinstance(packet, AckMessage):
            self._receive_ack(sender, packet)
            return
        self.unknown_inbound += 1

    def broadcast_hello(self) -> None:
        hello = ConductorHello(
            protocol_version=self.cfg.protocol_version,
            show_session_id=self.show_session_id,
            expected_device_count=self.cfg.expected_device_count,
            sent_at_ms=self.loop.now_ms,
        )
        self.hellos_sent += 1
        self.net.conductor_broadcast(hello)

    def send_cue_wave(self) -> None:
        for slot in range(1, self.cfg.clients + 1):
            cue = CueEnvelope(
                slot=slot,
                protocol_version=self.cfg.protocol_version,
                show_session_id=self.show_session_id,
                seq=self.next_seq,
                cue_id=str(uuid.uuid4()),
                sent_at_ms=self.loop.now_ms,
                payload=("flash/on", 1.0),
            )
            self.next_seq += 1
            self.cues_generated += 1
            self.pending_cues[(slot, cue.cue_id)] = cue.sent_at_ms

            for attempt in range(self.cfg.resend_attempts):
                delay = attempt * self.cfg.resend_spacing_ms
                self.loop.call_later(delay, lambda slot=slot, cue=cue: self.net.conductor_unicast(slot, cue))

    def _receive_client_hello(self, sender: str, hello: ClientHello) -> None:
        if not sender.startswith("client:"):
            self.unknown_inbound += 1
            return

        if hello.protocol_version != self.cfg.protocol_version:
            self.client_protocol_mismatches += 1
            return

        if hello.show_session_id and hello.show_session_id != self.show_session_id:
            self.client_session_mismatches += 1
            return

        self.hellos_received += 1
        self.paired_slots.add(hello.slot)

    def _receive_ack(self, sender: str, ack: AckMessage) -> None:
        if not sender.startswith("client:"):
            self.unknown_inbound += 1
            return

        if ack.protocol_version != self.cfg.protocol_version:
            self.client_protocol_mismatches += 1
            return

        if ack.show_session_id and ack.show_session_id != self.show_session_id:
            self.client_session_mismatches += 1
            return

        key = (ack.slot, ack.cue_id)
        sent_at = self.pending_cues.pop(key, None)
        if sent_at is None:
            self.duplicate_or_late_acks += 1
            return

        latency = max(0.0, float(self.loop.now_ms - sent_at))
        self.ack_latencies_ms.append(latency)
        self.acks_received += 1


class ConcertSimulation:
    def __init__(self, cfg: SimConfig) -> None:
        self.cfg = cfg
        self.rng = random.Random(cfg.seed)
        self.loop = SimLoop()
        self.net = ImpairedNetwork(self.loop, cfg, self.rng)
        self.conductor = SimConductor(self.loop, self.net, cfg)
        self.clients = {
            slot: SimClient(slot, self.loop, self.net, cfg)
            for slot in range(1, cfg.clients + 1)
        }
        self.net.attach(self.conductor, self.clients)

    def run(self) -> Dict[str, object]:
        until_ms = self.cfg.duration_sec * 1000
        self.conductor.schedule(until_ms)
        for client in self.clients.values():
            client.schedule(until_ms)

        self.loop.run(until_ms)
        # Allow in-flight packets and acks to settle after cue generation stops.
        self.loop.run(until_ms + self.cfg.settle_window_ms)
        return self._build_report()

    def _build_report(self) -> Dict[str, object]:
        per_client: List[Dict[str, object]] = []
        total_processed = 0
        total_dupes = 0
        total_out_of_order = 0
        total_unknown = 0
        total_protocol_mismatch = 0
        total_session_mismatch = 0

        for slot in sorted(self.clients):
            client = self.clients[slot]
            total_processed += client.cues_processed
            total_dupes += client.duplicates_ignored
            total_out_of_order += client.out_of_order_dropped
            total_unknown += client.unknown_sender_events
            total_protocol_mismatch += client.protocol_mismatch_dropped
            total_session_mismatch += client.session_mismatch_dropped

            per_client.append(
                {
                    "slot": slot,
                    "paired": client.is_paired,
                    "cues_processed": client.cues_processed,
                    "duplicates_ignored": client.duplicates_ignored,
                    "out_of_order_dropped": client.out_of_order_dropped,
                    "unknown_sender_events": client.unknown_sender_events,
                }
            )

        ack_ratio = (
            float(self.conductor.acks_received) / float(self.conductor.cues_generated)
            if self.conductor.cues_generated
            else 0.0
        )

        latencies = self.conductor.ack_latencies_ms
        ack_latency = {
            "count": len(latencies),
            "min_ms": min(latencies) if latencies else 0.0,
            "p50_ms": _percentile(latencies, 0.50),
            "p95_ms": _percentile(latencies, 0.95),
            "max_ms": max(latencies) if latencies else 0.0,
            "avg_ms": (sum(latencies) / len(latencies)) if latencies else 0.0,
        }

        failures: List[str] = []
        paired = len(self.conductor.paired_slots)
        if paired != self.cfg.clients:
            failures.append(f"paired_clients={paired}/{self.cfg.clients}")
        if ack_ratio < self.cfg.min_ack_ratio:
            failures.append(f"ack_ratio={ack_ratio:.3f} below {self.cfg.min_ack_ratio:.3f}")

        underfilled = [
            row["slot"]
            for row in per_client
            if int(row["cues_processed"]) < self.cfg.min_cues_per_client
        ]
        if underfilled:
            failures.append(
                f"clients_below_min_cues={len(underfilled)} (min={self.cfg.min_cues_per_client})"
            )

        status = "PASS" if not failures else "FAIL"

        return {
            "status": status,
            "failures": failures,
            "config": {
                "clients": self.cfg.clients,
                "duration_sec": self.cfg.duration_sec,
                "protocol_version": self.cfg.protocol_version,
                "expected_device_count": self.cfg.expected_device_count,
                "loss_pct": self.cfg.loss_pct,
                "jitter_ms": self.cfg.jitter_ms,
                "duplication_pct": self.cfg.duplication_pct,
                "reordering_pct": self.cfg.reordering_pct,
                "seed": self.cfg.seed,
            },
            "session": {
                "show_session_id": self.conductor.show_session_id,
                "paired_clients": paired,
                "expected_clients": self.cfg.clients,
                "hellos_sent": self.conductor.hellos_sent,
                "hellos_received": self.conductor.hellos_received,
            },
            "cue_metrics": {
                "cues_generated": self.conductor.cues_generated,
                "cues_processed_total": total_processed,
                "acks_received": self.conductor.acks_received,
                "ack_ratio": ack_ratio,
                "duplicates_ignored_total": total_dupes,
                "out_of_order_dropped_total": total_out_of_order,
                "protocol_mismatch_total": total_protocol_mismatch,
                "session_mismatch_total": total_session_mismatch,
                "unknown_sender_events_total": total_unknown,
                "duplicate_or_late_acks": self.conductor.duplicate_or_late_acks,
            },
            "ack_latency_ms": ack_latency,
            "network": {
                "attempted_packets": self.net.attempted_packets,
                "scheduled_deliveries": self.net.scheduled_deliveries,
                "dropped_packets": self.net.dropped_packets,
                "injected_duplicates": self.net.injected_duplicates,
            },
            "clients": per_client,
        }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Concert protocol stress simulator")
    parser.add_argument("--clients", type=int, default=28, help="number of simulated clients")
    parser.add_argument("--duration-sec", type=int, default=120, help="simulated show duration in seconds")
    parser.add_argument("--loss-pct", type=float, default=1.0, help="packet loss percentage")
    parser.add_argument("--jitter-ms", type=int, default=20, help="max jitter in milliseconds")
    parser.add_argument("--duplication-pct", type=float, default=2.0, help="packet duplication percentage")
    parser.add_argument("--reordering-pct", type=float, default=2.0, help="packet reordering percentage")
    parser.add_argument("--seed", type=int, default=42, help="RNG seed")
    parser.add_argument("--min-ack-ratio", type=float, default=0.95, help="minimum ack ratio required to pass")
    parser.add_argument(
        "--min-cues-per-client",
        type=int,
        default=1,
        help="minimum processed cues per client required to pass",
    )
    parser.add_argument("--json", action="store_true", help="print JSON summary")
    return parser.parse_args()


def print_human_report(report: Dict[str, object]) -> None:
    status = str(report["status"])
    cfg = report["config"]
    session = report["session"]
    cue = report["cue_metrics"]
    ack = report["ack_latency_ms"]
    network = report["network"]

    print("=== Concert Simulation Summary ===")
    print(
        f"Config: clients={cfg['clients']} duration={cfg['duration_sec']}s "
        f"loss={cfg['loss_pct']}% jitter={cfg['jitter_ms']}ms "
        f"dup={cfg['duplication_pct']}% reorder={cfg['reordering_pct']}% seed={cfg['seed']}"
    )
    print(
        f"Session: paired={session['paired_clients']}/{session['expected_clients']} "
        f"showSessionId={str(session['show_session_id'])[:8]}"
    )
    print(
        f"Cues: generated={cue['cues_generated']} processed_total={cue['cues_processed_total']} "
        f"acks={cue['acks_received']} ack_ratio={float(cue['ack_ratio']):.3f}"
    )
    print(
        f"Drops: duplicates={cue['duplicates_ignored_total']} out_of_order={cue['out_of_order_dropped_total']} "
        f"protocol_mismatch={cue['protocol_mismatch_total']} session_mismatch={cue['session_mismatch_total']} "
        f"unknown_sender={cue['unknown_sender_events_total']}"
    )
    print(
        f"Ack latency ms: min={float(ack['min_ms']):.1f} p50={float(ack['p50_ms']):.1f} "
        f"p95={float(ack['p95_ms']):.1f} max={float(ack['max_ms']):.1f} avg={float(ack['avg_ms']):.1f}"
    )
    print(
        f"Network: attempted={network['attempted_packets']} delivered={network['scheduled_deliveries']} "
        f"dropped={network['dropped_packets']} injected_duplicates={network['injected_duplicates']}"
    )

    print("Per-client cue metrics:")
    for row in report["clients"]:
        print(
            "  "
            f"slot {int(row['slot']):02d} | paired={str(row['paired']).lower():5s} "
            f"cues={int(row['cues_processed']):4d} dup={int(row['duplicates_ignored']):4d} "
            f"ooo={int(row['out_of_order_dropped']):4d} unknown={int(row['unknown_sender_events']):3d}"
        )

    if report["failures"]:
        print("Failures:")
        for failure in report["failures"]:
            print(f"  - {failure}")

    print(f"RESULT: {status}")


def main() -> int:
    args = parse_args()

    cfg = SimConfig(
        clients=args.clients,
        duration_sec=args.duration_sec,
        expected_device_count=args.clients,
        loss_pct=args.loss_pct,
        jitter_ms=args.jitter_ms,
        duplication_pct=args.duplication_pct,
        reordering_pct=args.reordering_pct,
        seed=args.seed,
        min_ack_ratio=args.min_ack_ratio,
        min_cues_per_client=args.min_cues_per_client,
    )

    report = ConcertSimulation(cfg).run()
    print_human_report(report)

    if args.json:
        import json

        print(json.dumps(report, indent=2))

    return 0 if report["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
