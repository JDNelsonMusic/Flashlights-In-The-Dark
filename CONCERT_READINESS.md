# Concert Readiness Runbook

Last updated: March 2, 2026

## Reliability Model (Protocol v2)

- **Single authority**: one trusted conductor endpoint per client session.
- **No peer mesh**: clients do not learn or promote peers as servers.
- **Session lock**: conductor emits a `showSessionId` (UUID); clients only execute cues for the locked session.
- **Version lock**: both sides enforce `protocolVersion` (`2`); mismatches fail safe.
- **Deterministic cue envelope**: every cue includes:
  - `slot`
  - `protocolVersion`
  - `showSessionId`
  - `seq` (monotonic)
  - `cueId` (UUID)
  - `sentAtMs`
  - payload
- **Receiver safety rules**:
  - serialized cue handling
  - `cueId` dedupe with TTL cache
  - strict sequence check (`seq <= lastSeq` is dropped)
- **Routing policy**:
  - broadcast: discovery/hello and panic all-stop only
  - unicast: all normal cues after endpoints are known

## What "Connected" Means

A device is considered connected only when all are true:

1. Client is paired to a trusted conductor endpoint (IP:port lock).
2. Client has a matching `showSessionId` and `protocolVersion`.
3. Heartbeats are fresh (conductor hello/traffic within timeout).

Connection is **not** sustained by peer traffic. If trusted conductor heartbeats stop, clients unpair and require a fresh valid hello.

## 28-Device Invariant

- `expectedDeviceCount` defaults to **28** in one source of truth (`ConcertProtocol.expectedDeviceCount`).
- Preflight and arming checks are based on `connectedPerformanceDeviceCount / expectedDeviceCount`.
- Placeholder slots are excluded from heartbeat/preflight counting.

## Pre-Show Checklist

1. Put all phones and conductor Mac on the dedicated closed Wi-Fi network.
2. Launch all 28 clients and verify app remains foregrounded.
3. Start conductor console; confirm preflight reaches **28/28 connected**.
4. Confirm no growing warnings in diagnostics:
   - unknown sender count
   - protocol/session mismatch counters
   - send failures
5. Verify interface health summary is populated and non-zero on active interfaces.
6. Keep console in **SAFE** until cue time.
7. Arm only when preflight is green, or use explicit override only if artistically necessary.

## SAFE / ARMED / PANIC

- **SAFE (default)**: cue sends are blocked.
- **ARMED**: cues enabled once strict preflight passes (or explicit override).
- **PANIC**: `/panic/all-stop` is always allowed and broadcasts fail-safe stop.

## Verification Commands

Run full hardening verification:

```bash
scripts/verify.sh
```

Run 10-minute simulated soak (simulated time):

```bash
scripts/soak_sim.sh
```

Useful overrides:

```bash
SIM_DURATION_SEC=300 scripts/soak_sim.sh
SIM_QUICK_DURATION_SEC=60 scripts/verify.sh
```

Direct simulator invocation:

```bash
python3 tools/concert_sim.py --clients 28 --duration-sec 120 --loss-pct 2 --jitter-ms 30 --duplication-pct 3 --reordering-pct 3
```

## Failure Modes and Operator Actions

- **Preflight below 28/28**:
  - Keep SAFE.
  - Use routing view to identify missing slots and last heartbeat times.
  - Request reconnect (discover/hello refresh) and relaunch affected client app(s).
- **Unknown sender count rises**:
  - Suspect rogue sender or wrong network.
  - Verify all devices are on the performance SSID only.
- **Protocol/session mismatches**:
  - Stop and restart session to regenerate consistent `showSessionId`.
  - Ensure all clients are on the same production build.
- **Send failures/interface errors**:
  - Check interface health diagnostics.
  - Keep operating if partial delivery persists but visible; do not ignore counters.
- **Cue anomalies during performance**:
  - Re-send cue safely (dedupe protects clients).
  - Use panic all-stop if state diverges.

## Deployment Notes

- Distribution is via **TestFlight** (iOS) and **Play Store** (Android).
- Legacy onboarding/provisioning scripts remain in `scripts/` for historical/debug use and are **deprecated for normal deployment**.
