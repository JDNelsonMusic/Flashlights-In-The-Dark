#!/usr/bin/env python3
"""
Flashlights-in-the-Dark  •  mini OSC control panel
--------------------------------------------------
• Lets you type a Singer ID and torch intensity, then send /flash/on or /flash/off
• Shows the exact OSC packet that was just transmitted
• Warns you if python-osc is missing or if inputs aren’t valid numbers
"""

import sys
import socket
import tkinter as tk
from tkinter import messagebox

# ───────────────────────────── python-osc import ──────────────────────────
try:
    from pythonosc.udp_client import SimpleUDPClient
except ModuleNotFoundError:
    messagebox.showerror(
        "python-osc missing",
        "The python-osc package isn’t installed.\n\n"
        "Fix it with:\n    pip install python-osc"
    )
    sys.exit(1)

# ───────────────────────────── configuration ──────────────────────────────
#
# By default we use the subnet-broadcast address (e.g. 192.168.8.255).
# It tends to work on more routers than 255.255.255.255.
#
def default_broadcast() -> str:
    """Return xxx.xxx.xxx.255 for the first non-loopback interface."""
    try:
        hostname = socket.gethostname()
        ip = socket.gethostbyname(hostname)
        parts = ip.split(".")
        parts[-1] = "255"
        return ".".join(parts)
    except Exception:
        return "255.255.255.255"

DEST_IP   = "192.168.0.150"
DEST_PORT = 9000

client = SimpleUDPClient(DEST_IP, DEST_PORT, allow_broadcast=True)

# ───────────────────────────── helpers ────────────────────────────────────
def flash_on() -> None:
    idx, intensity = _validated_inputs(require_intensity=True)
    if idx is None:                       # validation failed
        return
    _send("/flash/on", [idx, intensity])

def flash_off() -> None:
    idx, _ = _validated_inputs(require_intensity=False)
    if idx is None:
        return
    _send("/flash/off", [idx])

def _validated_inputs(require_intensity: bool):
    try:
        idx = int(idx_var.get())
    except ValueError:
        messagebox.showwarning("Input error", "Singer index must be an integer")
        return None, None

    if require_intensity:
        try:
            intensity = float(intensity_var.get())
        except ValueError:
            messagebox.showwarning("Input error", "Intensity must be a float (0-1)")
            return None, None
    else:
        intensity = 0.0                      # ignored

    return idx, intensity

def _send(address: str, args: list) -> None:
    try:
        client.send_message(address, args)
        status.set(f"✅ Sent {address} {args} → {DEST_IP}:{DEST_PORT}")
    except Exception as e:
        status.set(f"❌ Error: {e}")
        messagebox.showerror("Send failed", str(e))

# ───────────────────────────── UI  — Tkinter ──────────────────────────────
root = tk.Tk()
root.title("Flashlights OSC Panel")
root.resizable(False, False)

# Singer index
tk.Label(root, text="Singer ID").grid(row=0, column=0, padx=6, pady=4, sticky="e")
idx_var = tk.StringVar(value="0")
tk.Entry(root, textvariable=idx_var, width=6).grid(row=0, column=1, padx=3, pady=4)

# Intensity
tk.Label(root, text="Intensity (0–1)").grid(row=1, column=0, padx=6, pady=4, sticky="e")
intensity_var = tk.StringVar(value="1.0")
tk.Entry(root, textvariable=intensity_var, width=6).grid(row=1, column=1, padx=3, pady=4)

# Buttons
tk.Button(root, text="Flash  ON",  width=12, command=flash_on ).grid(row=2, column=0, pady=10)
tk.Button(root, text="Flash OFF",  width=12, command=flash_off).grid(row=2, column=1, pady=10)

# Status bar
status = tk.StringVar(value=f"Ready  →  broadcasting to {DEST_IP}:{DEST_PORT}")
tk.Label(root, textvariable=status, fg="navy").grid(row=3, column=0, columnspan=2, pady=(0,8))

root.mainloop()
