#!/usr/bin/env python3
"""
Flashlights-in-the-Dark • v9.0  (18 May 2025)
───────────────────────────────────────────────────────────────────────────────
32‑lamp “Photo‑Acoustic” grid ↔ typing keyboard ↔ virtual + hardware MIDI

• Full polyphony & sustain (SPACE)               – unchanged
• “0” key drives an ADSR‑shaped light envelope (user‑tunable)
• NEW in v9.0
  • ⏎ / Return commits ADSR spin‑box edits and deselects the field
  • Clicking anywhere outside a spin‑box also deselects it
  • Clicking on any lamp plays / releases the corresponding note just like
    pressing its keyboard key (supports sustain)
  • Minor refactors & tidy‑ups

Tested on macOS Sequoia / Python 3.12 / Tk 8.6.13
"""

from __future__ import annotations
import sys, queue, threading, tkinter as tk, tkinter.ttk as ttk, tkinter.messagebox as mb
from dataclasses import dataclass, field
from typing import Dict, Tuple, Optional, Union, Set

# ──────────────────── MIDI backend ────────────────────
try:
    import mido  # needs python‑rtmidi backend
    MIDI_OK = True
except ImportError:
    MIDI_OK = False
    print("⚠️  mido / python-rtmidi not found – MIDI disabled", file=sys.stderr)

VM_OUT_NAME = "Flashlights Out"
VM_IN_NAME  = "Flashlights In"
SUSTAIN_CC       = 64
ALL_NOTES_OFF_CC = 123

QueueItem = Union[Tuple[int, bool], str, Tuple[str, str]]

# ──────────────────── Config ───────────────────────────
@dataclass(frozen=True)
class Config:
    rows: int = 4
    cols: int = 8
    key_rows: Tuple[str, ...] = ("12345678", "qwertyui", "asdfghjk", "zxcvbnm,")
    note_offsets: Tuple[int, ...] = (0, 1, 3, 4, 7, 8, 10, 11)
    base_note: int = 36
    all_note: int = 84
    RELEASE_DELAY_MS: int = 40
    ENV_DT_MS: int = 20            # frame period for ADSR animation (ms)

    bg: str = "#140014"
    lamp_off: str = "#331133"
    lamp_on: str = "#99ffdd"
    lamp_outline: str = "#ccffef"

    cell: int = 60
    pad: int = 20

    note_to_slot: Dict[int, int] = field(init=False, default_factory=dict)
    slot_to_note: Dict[int, int] = field(init=False, default_factory=dict)
    key_to_slot:  Dict[str, int] = field(init=False, default_factory=dict)

    def __post_init__(self):
        object.__setattr__(self, "note_to_slot",
            {self.base_note + r*12 + off: r*self.cols + c
             for r in range(self.rows) for c, off in enumerate(self.note_offsets)})
        object.__setattr__(self, "slot_to_note",
            {v: k for k, v in self.note_to_slot.items()})
        object.__setattr__(self, "key_to_slot",
            {ch: r*self.cols + c for r, row in enumerate(self.key_rows)
             for c, ch in enumerate(row)})

CFG = Config()

# ──────────────────── LampGrid ─────────────────────────
class LampGrid(tk.Canvas):
    """Draws & animates the 32 lamps.  Handles mouse clicks → note‑on/off."""
    def __init__(self, master: tk.Widget, note_callback):
        super().__init__(master,
            width=CFG.cols*CFG.cell + 2*CFG.pad,
            height=CFG.rows*CFG.cell + 2*CFG.pad,
            bg=CFG.bg, highlightthickness=0)
        self._ovals = tuple(self._make_cell(i) for i in range(CFG.rows*CFG.cols))
        self._rgb_off = self._hex_to_rgb(CFG.lamp_off)
        self._rgb_on  = self._hex_to_rgb(CFG.lamp_on)

        self._brightness: float = 0.0       # 0‑1 scalar for ADSR “ALL” mode
        self._env_jobs: list[str] = []      # after‑id strings

        # Mouse → note routing
        self._note_cb = note_callback       # (slot:int, on:bool) → None
        self._click_slot: Optional[int] = None
        self.bind("<ButtonPress-1>", self._on_press)
        self.bind("<ButtonRelease-1>", self._on_release)

    # ── colour helpers ────────────────────────────────
    @staticmethod
    def _hex_to_rgb(hexstr: str) -> Tuple[int, int, int]:
        hexstr = hexstr.lstrip("#")
        return tuple(int(hexstr[i:i+2], 16) for i in (0, 2, 4))

    @staticmethod
    def _rgb_to_hex(rgb: Tuple[int, int, int]) -> str:
        return "#%02x%02x%02x" % rgb

    def _blend(self, t: float) -> str:
        r = tuple(int(a + (b - a) * t) for a, b in zip(self._rgb_off, self._rgb_on))
        return self._rgb_to_hex(r)

    # ── cell creation ────────────────────────────────
    def _make_cell(self, idx: int):
        r, c = divmod(idx, CFG.cols)
        x, y = CFG.pad + c*CFG.cell, CFG.pad + r*CFG.cell
        outer = self.create_oval(x, y, x+CFG.cell, y+CFG.cell,
                                 fill=CFG.lamp_off, outline="")
        inner = self.create_oval(x+8, y+8, x+CFG.cell-8, y+CFG.cell-8,
                                 fill=CFG.lamp_off, outline="")
        return outer, inner

    # ── instantaneous state set ──────────────────────
    def set(self, idx: int, on: bool):
        if 0 <= idx < len(self._ovals):
            fill = CFG.lamp_on if on else CFG.lamp_off
            outline = CFG.lamp_outline if on else ""
            width = 3 if on else 0
            o, i = self._ovals[idx]
            self.itemconfigure(o, fill=fill, outline=outline, width=width)
            self.itemconfigure(i, fill=fill)

    def set_all(self, on: bool):
        for i in range(len(self._ovals)):
            self.set(i, on)

    # ── Mouse → slot helpers ─────────────────────────
    def _coords_to_slot(self, x: int, y: int) -> Optional[int]:
        x -= CFG.pad; y -= CFG.pad
        if x < 0 or y < 0:
            return None
        c, r = x // CFG.cell, y // CFG.cell
        if 0 <= r < CFG.rows and 0 <= c < CFG.cols:
            return r*CFG.cols + c
        return None

    def _on_press(self, e: tk.Event):
        slot = self._coords_to_slot(e.x, e.y)
        if slot is None:
            return
        self._click_slot = slot
        self._note_cb(slot, True)   # note‑on

    def _on_release(self, _e: tk.Event):
        if self._click_slot is not None:
            self._note_cb(self._click_slot, False)  # note‑off
            self._click_slot = None

    # ── ADSR envelope API (used by ALL/“0” mode) ────
    def _cancel_env(self):
        for job in self._env_jobs:
            self.after_cancel(job)
        self._env_jobs.clear()

    def _update_brightness(self):
        t = self._brightness
        col = self._blend(t)
        out_w = int(3 * t)
        for o, i in self._ovals:
            self.itemconfigure(o, fill=col,
                               outline=CFG.lamp_outline if t else "",
                               width=out_w)
            self.itemconfigure(i, fill=col)

    def _schedule_phase(self, target: float, duration_ms: int,
                        then: Optional[callable] = None):
        start = self._brightness
        steps = max(duration_ms // CFG.ENV_DT_MS, 1)
        def frame(i=0):
            nonlocal steps
            self._brightness = start + (target - start) * (i / steps)
            self._update_brightness()
            if i < steps:
                job = self.after(CFG.ENV_DT_MS, frame, i+1)
                self._env_jobs.append(job)
            else:
                if then:
                    then()
        frame()

    def envelope_start(self, a_ms: int, d_ms: int, sustain_pct: int):
        """Begin attack+decay, hold at sustain while key held."""
        self._cancel_env()
        sustain_level = max(0, min(100, sustain_pct)) / 100.0
        def begin_decay():
            self._schedule_phase(sustain_level, d_ms)
        self._schedule_phase(1.0, a_ms, begin_decay)

    def envelope_release(self, r_ms: int):
        """Fade from current level to 0 over r_ms."""
        self._cancel_env()
        self._schedule_phase(0.0, r_ms)

    def stop_animation(self):
        """Immediately stop ADSR animation and blank lamps."""
        self._cancel_env()
        self._brightness = 0.0
        self._update_brightness()

# ──────────────────── MIDI listener thread ───────────

def midi_in_worker(port_name: str, q: "queue.Queue[QueueItem]",
                   stop: threading.Event, *, virtual: bool = False):
    try:
        with mido.open_input(port_name, virtual=virtual) as port:
            while not stop.is_set():
                for msg in port.iter_pending():
                    if msg.type not in ("note_on", "note_off"):
                        continue
                    if msg.note == CFG.all_note:
                        q.put("ALL"); continue
                    slot = CFG.note_to_slot.get(msg.note)
                    if slot is not None:
                        q.put((slot, msg.type == "note_on" and msg.velocity > 0))
                stop.wait(0.001)
    except Exception as exc:
        q.put(("ERROR", f"{port_name}: {exc}"))

# ──────────────────── Main application ──────────────
class App(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("Flashlights MIDI Simulator")
        self.configure(bg=CFG.bg)
        self.resizable(False, False)
        self._adapt_to_hi_dpi()

        self.queue: "queue.Queue[QueueItem]" = queue.Queue()
        self.stop_event = threading.Event()

        self.midi_out: Optional["mido.ports.BaseOutput"] = None
        self.worker: Optional[threading.Thread] = None
        self.use_keyboard = True

        # ── keyboard / sustain state ──
        self.active_keys: Dict[int, int] = {}
        self.pending_off: Dict[int, str] = {}
        self.held_slots: Set[int]      = set()
        self.sustained_slots: Set[int] = set()
        self.sustain_on: bool          = False
        self.all_on_slots: Set[int]    = set()

        self._setup_virtual_midi()

        # ── UI ──
        self._build_topbar()
        self.grid_widget = LampGrid(self, self._mouse_note)
        self.grid_widget.pack(padx=CFG.pad, pady=CFG.pad)
        self._build_adsr_controls()

        # Global shortcuts / event bindings
        self.bind_all("<Command-BackSpace>", lambda _: self._panic())
        self.bind_all("<Control-BackSpace>",  lambda _: self._panic())
        self.bind("<KeyPress>",  self._on_key)
        self.bind("<KeyRelease>", self._on_key)
        self.bind_all("<Return>", self._on_return_key)
        self.bind_all("<Button-1>", self._on_global_click, add="+")

        self.after(20, self._process_queue)
        self.protocol("WM_DELETE_WINDOW", self._on_close)
        self._switch_input()

    # ───────────────── Hi‑DPI fix ────────────────────
    def _adapt_to_hi_dpi(self):
        try:
            sc = float(self.tk.call("tk", "scaling"))
            if sc >= 2.0:
                self.tk.call("tk", "scaling", sc/2.0)
        except Exception:
            pass

    # ───────────────── Focus helpers ────────────────
    def _on_return_key(self, _e: tk.Event):
        """⏎ while editing a spin‑box → commit & defocus (select grid)."""
        if isinstance(self.focus_get(), (tk.Entry, ttk.Entry, tk.Spinbox, ttk.Spinbox)):
            self.grid_widget.focus_set()

    def _on_global_click(self, e: tk.Event):
        """Clicking anywhere not on an Entry/Spinbox → defocus those widgets."""
        if not isinstance(e.widget, (tk.Entry, ttk.Entry, tk.Spinbox, ttk.Spinbox)):
            self.grid_widget.focus_set()

    # ───────────────── MIDI helpers ───────────────────
    def _send_cc(self, cc: int, value: int):
        if self.midi_out:
            self.midi_out.send(mido.Message("control_change",
                control=cc, value=value, channel=self.chan_var.get()-1))

    def _send_pc(self, program: int):
        if self.midi_out:
            self.midi_out.send(mido.Message("program_change",
                program=program, channel=self.chan_var.get()-1))

    def _panic(self):
        """Immediate all‑notes‑off (UI + MIDI)."""
        self.grid_widget.stop_animation()
        self._send_cc(ALL_NOTES_OFF_CC, 0)
        if self.midi_out:
            ch = self.chan_var.get() - 1
            for slot in range(CFG.rows*CFG.cols):
                self.midi_out.send(mido.Message("note_off",
                    note=CFG.slot_to_note[slot], velocity=0, channel=ch))
        self.grid_widget.set_all(False)
        self.held_slots.clear(); self.sustained_slots.clear()
        self.active_keys.clear(); self.pending_off.clear()
        self.all_on_slots.clear()
        self.sustain_on = False

    # ───────────────── Virtual MIDI setup ─────────────
    def _setup_virtual_midi(self):
        if not MIDI_OK:
            return
        outs = mido.get_output_names()
        if VM_OUT_NAME in outs:
            mb.showwarning("Flashlights already running?",
                "A virtual port named ‘Flashlights Out’ already exists.")
            self.midi_out = mido.open_output(VM_OUT_NAME)
        else:
            self.midi_out = mido.open_output(VM_OUT_NAME, virtual=True)
            print(f"🎹 Virtual MIDI OUT ‘{VM_OUT_NAME}’ created")

        threading.Thread(target=midi_in_worker,
                         args=(VM_IN_NAME, self.queue, self.stop_event),
                         kwargs={"virtual": True}, daemon=True).start()
        print(f"🎧 Virtual MIDI IN  ‘{VM_IN_NAME}’ ready (listener running)")

    # ───────────────── Toolbar ────────────────────────
    def _build_topbar(self):
        bar = tk.Frame(self, bg=CFG.bg); bar.pack(pady=6)

        # Input selector
        tk.Label(bar, text="Input:", fg="white", bg=CFG.bg).grid(row=0, column=0, sticky="e")
        self.port_var = tk.StringVar()
        self.dd_input = ttk.Combobox(bar, state="readonly")
        self.dd_input.grid(row=0, column=1, padx=4)
        self.dd_input.bind("<<ComboboxSelected>>", lambda *_: self._switch_input())

        # Channel
        tk.Label(bar, text="Ch.", fg="white", bg=CFG.bg).grid(row=0, column=2, sticky="e")
        self.chan_var = tk.IntVar(value=1)
        ttk.Spinbox(bar, from_=1, to=16, width=3, textvariable=self.chan_var).grid(row=0, column=3, padx=4)

        # Velocity slider
        tk.Label(bar, text="Velocity", fg="white", bg=CFG.bg).grid(row=0, column=4, sticky="e")
        self.vel_var = tk.IntVar(value=127)
        self.slider = ttk.Scale(bar, from_=1, to=127, orient="horizontal",
                                   length=120, variable=self.vel_var,
                                   command=lambda *_: self.lbl_vel.config(text=str(self.vel_var.get())))
        self.slider.grid(row=0, column=5, padx=(4, 0))
        self.lbl_vel = tk.Label(bar, text="127", fg="white", bg=CFG.bg, width=3)
        self.lbl_vel.grid(row=0, column=6, padx=(2, 6))

        # Mirror IN->OUT
        self.echo_var = tk.BooleanVar(master=self, value=False)
        ttk.Checkbutton(bar, text="Mirror IN → OUT", variable=self.echo_var).grid(row=0, column=7, padx=4)

        # ALL OFF
        ttk.Button(bar, text="ALL OFF", command=self._panic).grid(row=0, column=8, padx=(0, 6))

        # --- New MIDI utilities ---------------------------------
        tk.Label(bar, text="CC#", fg="white", bg=CFG.bg).grid(row=0, column=9, sticky="e")
        self.cc_num = tk.IntVar(value=1)
        ttk.Spinbox(bar, from_=0, to=127, width=4, textvariable=self.cc_num).grid(row=0, column=10, padx=2)
        tk.Label(bar, text="Val", fg="white", bg=CFG.bg).grid(row=0, column=11, sticky="e")
        self.cc_val = tk.IntVar(value=127)
        ttk.Spinbox(bar, from_=0, to=127, width=4, textvariable=self.cc_val).grid(row=0, column=12, padx=2)
        ttk.Button(bar, text="Send CC", command=lambda: self._send_cc(self.cc_num.get(), self.cc_val.get())).grid(row=0, column=13, padx=(0, 8))

        # Program‑Change sender
        tk.Label(bar, text="Prog", fg="white", bg=CFG.bg).grid(row=0, column=14, sticky="e")
        self.prog_var = tk.IntVar(value=0)
        ttk.Spinbox(bar, from_=0, to=127, width=4, textvariable=self.prog_var).grid(row=0, column=15, padx=2)
        ttk.Button(bar, text="Send PC", command=lambda: self._send_pc(self.prog_var.get())).grid(row=0, column=16, padx=(0, 4))

        # Menu
        menu = tk.Menu(self, tearoff=False)
        menu.add_command(label="Refresh Inputs", command=self._refresh_inputs)
        self.config(menu=menu)

        self._refresh_inputs()
        if not MIDI_OK:
            self.dd_input.config(state="disabled")

    # ───────────────── Input refresh ─────────────────
    def _refresh_inputs(self):
        ports = ["Typing Keyboard"]
        if MIDI_OK:
            ports += [p for p in mido.get_input_names() if p != VM_IN_NAME]
        self.dd_input["values"] = ports
        if self.port_var.get() not in ports:
            self.port_var.set(ports[0])
        self.dd_input.set(self.port_var.get())

    # ───────────────── ADSR footer ───────────────────
    def _build_adsr_controls(self):
        f = tk.Frame(self, bg=CFG.bg); f.pack(pady=(0, 6))

        # IntVars
        self.attack_var  = tk.IntVar(value=500)
        self.decay_var   = tk.IntVar(value=500)
        self.sustain_var = tk.IntVar(value=70)
        self.release_var = tk.IntVar(value=500)

        def spin(var, to, w=5):
            return ttk.Spinbox(f, from_=0, to=to, width=w, textvariable=var)

        lbl_kwargs = dict(fg="white", bg=CFG.bg)

        tk.Label(f, text="A ms", **lbl_kwargs).grid(row=0, column=0, sticky="e")
        spin(self.attack_var, 5000).grid(row=0, column=1, padx=2)
        tk.Label(f, text="D ms", **lbl_kwargs).grid(row=0, column=2, sticky="e")
        spin(self.decay_var, 5000).grid(row=0, column=3, padx=2)
        tk.Label(f, text="S %", **lbl_kwargs).grid(row=0, column=4, sticky="e")
        spin(self.sustain_var, 100).grid(row=0, column=5, padx=2)
        tk.Label(f, text="R ms", **lbl_kwargs).grid(row=0, column=6, sticky="e")
        spin(self.release_var, 5000).grid(row=0, column=7, padx=2)

        tk.Label(self,
                 text="Typing rows: " + " ".join(CFG.key_rows) +
                      "   (SPACE = sustain, 0 = ALL w/ADSR)",
                 fg="#bbbbbb", bg=CFG.bg).pack()

    # ───────────────── Input switching ───────────────
    def _switch_input(self):
        if self.worker and self.worker.is_alive():
            self.stop_event.set(); self.worker.join(); self.stop_event.clear()

        self._panic()  # clear state/UI

        sel = self.dd_input.get()
        self.use_keyboard = sel == "Typing Keyboard" or not MIDI_OK
        if self.use_keyboard:
            return

        self.worker = threading.Thread(target=midi_in_worker,
                                       args=(sel, self.queue, self.stop_event),
                                       daemon=True).start()

    # ───────────────── Key helpers ───────────────────
    def _keysym(self, e: tk.Event) -> str:
        if e.char and e.char.isprintable():
            return e.char.lower()
        return e.keysym.lower()

    # ───────────────── Mouse (lamp) note helpers ────
    def _mouse_note(self, slot: int, on: bool):
        """Called by LampGrid when user clicks a lamp."""
        if on:
            self.held_slots.add(slot)
            self.sustained_slots.discard(slot)
            self._set_slot(slot, True, send=True)
        else:
            self.held_slots.discard(slot)
            if self.sustain_on:
                self.sustained_slots.add(slot)
            else:
                self._set_slot(slot, False, send=True)

    # ───────────────── Key handling ──────────────────
    def _on_key(self, e: tk.Event):
        if not self.use_keyboard:
            return

        kc = e.keycode
        ks = self._keysym(e)
        is_press = e.type == tk.EventType.KeyPress

        # ---------- KeyPress ----------
        if is_press:
            if kc in self.pending_off:
                self.after_cancel(self.pending_off.pop(kc))
            if kc in self.active_keys:      # OS repeat debounce
                return

            # Sustain pedal
            if ks == " ":
                self.active_keys[kc] = -1
                self.sustain_on = True
                self._send_cc(SUSTAIN_CC, 127)
                return

            # ALL/ADSR trigger on “0”
            if ks == "0":
                self.active_keys[kc] = -2
                self.all_on_slots = set(range(CFG.rows*CFG.cols))
                # Start ADSR envelope
                self.grid_widget.envelope_start(
                    self.attack_var.get(),
                    self.decay_var.get(),
                    self.sustain_var.get())
                # MIDI
                vel = self.vel_var.get()
                chn = self.chan_var.get() - 1
                if self.midi_out:
                    for slot in self.all_on_slots:
                        note = CFG.slot_to_note[slot]
                        self.midi_out.send(mido.Message("note_on",
                            note=note, velocity=vel, channel=chn))
                return

            # Normal note
            slot = CFG.key_to_slot.get(ks)
            if slot is None:
                return
            self.active_keys[kc] = slot
            self.held_slots.add(slot)
            self.sustained_slots.discard(slot)
            self._set_slot(slot, True, send=True)
            return

        # ---------- KeyRelease ----------
        def really_release():
            self.pending_off.pop(kc, None)
            slot = self.active_keys.pop(kc, None)
            if slot is None:
                return

            # Pedal up
            if slot == -1:
                self.sustain_on = False
                self._send_cc(SUSTAIN_CC, 0)
                for s in list(self.sustained_slots):
                    if s not in self.held_slots:
                        self.sustained_slots.remove(s)
                        self._set_slot(s, False, send=True)
                return

            # “0” released → envelope release
            if slot == -2:
                self.grid_widget.envelope_release(self.release_var.get())
                chn = self.chan_var.get() - 1
                vel0 = 0
                for s in list(self.all_on_slots):
                    if s in self.held_slots or s in self.sustained_slots:
                        continue
                    self._set_slot(s, False, send=True)
                    if self.midi_out:
                        note = CFG.slot_to_note[s]
                        self.midi_out.send(mido.Message("note_off",
                            note=note, velocity=vel0, channel=chn))
                self.all_on_slots.clear()
                return

            # Normal key release
            self.held_slots.discard(slot)
            if self.sustain_on:
                self.sustained_slots.add(slot)
            else:
                self._set_slot(slot, False, send=True)

        if kc not in self.pending_off:
            self.pending_off[kc] = self.after(CFG.RELEASE_DELAY_MS, really_release)

    # ───────────────── Grid + MIDI ───────────────────
    def _set_slot(self, slot: int, on: bool, *, send: bool):
        self.grid_widget.set(slot, on)
        if send and self.midi_out:
            self.midi_out.send(mido.Message("note_on" if on else "note_off",
                note=CFG.slot_to_note[slot],
                velocity=self.vel_var.get() if on else 0,
                channel=self.chan_var.get() - 1))

    # ───────────────── Queue polling ────────────────
    def _process_queue(self):
        try:
            while True:
                item = self.queue.get_nowait()
                if item == "ALL":
                    self._panic()
                elif isinstance(item, tuple) and len(item) == 2:
                    slot, on = item
                    self._set_slot(slot, on, send=self.echo_var.get())
                elif isinstance(item, tuple) and item[0] == "ERROR":
                    mb.showerror("MIDI error", item[1])
        except queue.Empty:
            pass
        finally:
            self.after(20, self._process_queue)

    # ───────────────── Clean shutdown ───────────────
    def _on_close(self):
        self._panic()
        self.stop_event.set()
        if self.worker and self.worker.is_alive():
            self.worker.join(1.0)
        if self.midi_out:
            self.midi_out.close()
        self.destroy()

# ───────────────── Entry ────────────────────────────
if __name__ == "__main__":
    App().mainloop()
