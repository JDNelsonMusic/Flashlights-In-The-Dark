#!/usr/bin/env python3
"""Tiny OSC control panel for Flashlights-in-the-Dark."""
import sys
import tkinter as tk
from tkinter import messagebox

try:
    from pythonosc.udp_client import SimpleUDPClient
except ModuleNotFoundError:
    messagebox.showerror(
        "python-osc missing",
        "The python-osc package is not installed.\n\n"
        "Fix it with:\n    pip install python-osc"
    )
    sys.exit(1)

# --- config ---------------------------------------------------------------
BROADCAST_IP = "255.255.255.255"
PORT         = 9000
client       = SimpleUDPClient(BROADCAST_IP, PORT, allow_broadcast=True)
# --------------------------------------------------------------------------

def flash_on():
    try:
        idx  = int(singer_var.get())
        gain = float(intensity_var.get())
    except ValueError:
        messagebox.showwarning("Input error", "Index and intensity must be numbers")
        return
    client.send_message("/flash/on", [idx, gain])

def flash_off():
    try:
        idx = int(singer_var.get())
    except ValueError:
        messagebox.showwarning("Input error", "Index must be a number")
        return
    client.send_message("/flash/off", [idx])

# --- UI -------------------------------------------------------------------
root = tk.Tk()
root.title("Flashlights OSC Panel")
root.resizable(False, False)

tk.Label(root, text="Singer index").grid(row=0, column=0, padx=6, pady=4, sticky="e")
singer_var = tk.StringVar(value="0")
tk.Entry(root, textvariable=singer_var, width=5).grid(row=0, column=1, pady=4, sticky="w")

tk.Label(root, text="Intensity (0–1)").grid(row=1, column=0, padx=6, pady=4, sticky="e")
intensity_var = tk.StringVar(value="1.0")
tk.Entry(root, textvariable=intensity_var, width=5).grid(row=1, column=1, pady=4, sticky="w")

tk.Button(root, text="Flash ON",  width=10, command=flash_on ).grid(row=2, column=0, pady=10)
tk.Button(root, text="Flash OFF", width=10, command=flash_off).grid(row=2, column=1, pady=10)

root.mainloop()
