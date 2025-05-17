#!/usr/bin/env python3
"""
Flashlights-in-the-Dark • MIDI / Keyboard control simulator
────────────────────────────────────────────────────────────
• 32 mint-glow lamps on a deep-purple stage.
• Pick any MIDI-IN port *or* “Keyboard (Builtin)” from drop-down.
• MIDI:   C2…B  • C3…B  • C4…B  • C5…B   rows  (8 notes each)
          C6 Note-On toggles ALL lamps.
• Keys:   12345678  qwertyui  asdfghjk  zxcvbnm,   (space = ALL)
"""

import sys, threading, queue, itertools
import tkinter as tk
from tkinter import ttk, messagebox

# ───────────────────────────── MIDI support ────────────────────────────
try:
    import mido                    # needs python-rtmidi backend
    MIDI_OK = True
except ImportError:
    MIDI_OK = False

# note mapping (same as previous)
NOTE_OFFSETS = (0, 1, 3, 4, 7, 8, 10, 11)
ROWS, COLS   = 4, 8
ALL_NOTE     = 84                             # C6

note_to_slot = {36 + r*12 + off : r*COLS + c
                for r in range(ROWS)
                for c, off in enumerate(NOTE_OFFSETS)}

# ───────────────────────────── keyboard map ────────────────────────────
KEY_ROWS = (
    "12345678",
    "qwertyui",
    "asdfghjk",
    "zxcvbnm,"
)
KEY_TO_SLOT = {ch: r*COLS + c
               for r,row in enumerate(KEY_ROWS)
               for c,ch in enumerate(row)}

# ───────────────────────────── visuals ─────────────────────────────────
BG_PURPLE   = "#330033"
OFF_FILL    = "#442244"
ON_FILL     = "#99ffdd"
ON_OUTLINE  = "#ccffef"
CELL, PAD   = 60, 20

class LampGrid(tk.Canvas):
    def __init__(self, master):
        super().__init__(master, width=COLS*CELL+2*PAD,
                         height=ROWS*CELL+2*PAD, bg=BG_PURPLE,
                         highlightthickness=0)
        self.lamps = []
        for idx in range(ROWS*COLS):
            r,c = divmod(idx, COLS)
            x,y = PAD + c*CELL, PAD + r*CELL
            outer = self.create_oval(x, y, x+CELL, y+CELL,
                                      outline="", fill=OFF_FILL)
            inner = self.create_oval(x+8, y+8, x+CELL-8, y+CELL-8,
                                      outline="", fill=OFF_FILL)
            self.lamps.append((outer,inner))

    def set(self, idx:int, on:bool):
        if 0 <= idx < len(self.lamps):
            fil, out = (ON_FILL, ON_OUTLINE) if on else (OFF_FILL,"")
            o,i = self.lamps[idx]
            self.itemconfigure(o, fill=fil, outline=out, width=3 if on else 0)
            self.itemconfigure(i, fill=fil)

    def any_off(self):                       # used by ALL toggle
        return any(self.itemcget(o,"fill")==OFF_FILL for o,_ in self.lamps)

    def set_all(self,on:bool):
        for i in range(len(self.lamps)): self.set(i,on)

# ───────────────────────────── MIDI worker  ────────────────────────────
def midi_worker(port_name, q:queue.Queue):
    with mido.open_input(port_name) as port:
        for msg in port:
            if msg.type not in ('note_on','note_off'): continue
            if msg.note == ALL_NOTE and msg.type=='note_on' and msg.velocity>0:
                q.put(('all',))
                continue
            slot = note_to_slot.get(msg.note)
            if slot is None: continue
            on = (msg.type=='note_on' and msg.velocity>0)
            q.put((slot,on))

# ───────────────────────────── main app  ───────────────────────────────
class App(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("Flashlights Controller Simulator")
        self.configure(bg=BG_PURPLE)
        self.resizable(False,False)

        # dropdown
        tk.Label(self,text="Input:",fg="white",bg=BG_PURPLE).pack(pady=(10,2))
        self.port_var = tk.StringVar()
        midi_ports = mido.get_input_names() if MIDI_OK else []
        self.ports = ["Keyboard (Builtin)"] + midi_ports
        self.dd = ttk.Combobox(self,values=self.ports,textvariable=self.port_var,
                               state="readonly",width=max(map(len,self.ports)))
        self.dd.pack()
        self.dd.bind("<<ComboboxSelected>>",self.change_source)
        self.port_var.set(self.ports[0])           # default

        # grid
        self.grid = LampGrid(self); self.grid.pack(padx=PAD,pady=PAD)

        # footnote
        tk.Label(self,text="Keys 12345678 qwertyui asdfghjk zxcvbnm,  (space = ALL)",
                 fg="#bbbbbb",bg=BG_PURPLE).pack(pady=(0,8))

        # state
        self.q = queue.Queue()
        self.midi_thread = None
        self.kbd_enabled = False

        self.change_source()              # spin up chosen input
        self.bind_events()
        self.after(30,self.poll_q)

    # ---- source selection -----------------
    def change_source(self,*_):
        sel = self.port_var.get()
        # stop existing MIDI thread if any
        if self.midi_thread and self.midi_thread.is_alive():
            self.midi_thread.do_run=False
        self.kbd_enabled = (sel=="Keyboard (Builtin)")
        if self.kbd_enabled:
            self.grid.set_all(False); return
        # MIDI
        try:
            t = threading.Thread(target=midi_worker,args=(sel,self.q),daemon=True)
            t.start(); self.midi_thread=t
            self.grid.set_all(False)
        except Exception as e:
            messagebox.showerror("MIDI error",str(e))

    # ---- keyboard binds -------------------
    def bind_events(self):
        self.bind("<KeyPress>",self.on_key)
        self.bind("<KeyRelease>",self.on_key)

    def on_key(self,e):
        if not self.kbd_enabled: return
        ch = e.char.lower()
        if ch==" " and e.type=="2":                # key press
            self.q.put(('all',))
            return
        slot = KEY_TO_SLOT.get(ch)
        if slot is None: return
        on = (e.type=="2")                        # 2=KeyPress, 3=KeyRelease
        self.grid.set(slot,on)

    # ---- poll queue ------------------------
    def poll_q(self):
        try:
            while True:
                item = self.q.get_nowait()
                if item[0]=='all':
                    self.grid.set_all(self.grid.any_off())
                else:
                    slot,on = item
                    self.grid.set(slot,on)
        except queue.Empty:
            pass
        self.after(30,self.poll_q)

if __name__=="__main__":
    App().mainloop()
