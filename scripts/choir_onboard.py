#!/usr/bin/env python3
"""
Script to onboard a singer's device: register in Apple Dev Portal, sync provisioning,
and assign to an available slot in flash_ip+udid_map.json.
"""
import argparse
import fcntl
import json
import os
import platform
import re
import subprocess
import sys


def get_udid(provided_udid=None):
    if provided_udid:
        return provided_udid
    try:
        out = subprocess.check_output(["idevice_id", "-l"]).decode().strip()
    except FileNotFoundError:
        sys.exit("Error: idevice_id not found. Install libimobiledevice.")
    except subprocess.CalledProcessError:
        sys.exit("Error: Failed to get UDID. Ensure device is trusted and connected.")
    lines = [l for l in out.splitlines() if l]
    if not lines:
        sys.exit("Error: No device found. Connect and trust this computer.")
    if len(lines) > 1:
        sys.exit("Error: Multiple devices found. Specify --udid to disambiguate.")
    return lines[0].strip()


def detect_ip(provided_ip=None):
    if provided_ip:
        return provided_ip
    system = platform.system()
    if system == "Darwin":
        try:
            ports = subprocess.check_output(
                ["networksetup", "-listallhardwareports"]
            ).decode().splitlines()
            for i, line in enumerate(ports):
                if line.strip() == "Hardware Port: iPhone USB":
                    for l in ports[i + 1 : i + 4]:
                        if l.strip().startswith("Device:"):
                            dev = l.split("Device:", 1)[1].strip()
                            ip = subprocess.check_output(["ipconfig", "getifaddr", dev])
                            return ip.decode().strip()
        except Exception:
            pass
    if system == "Linux":
        try:
            out = subprocess.check_output(["ip", "route", "get", "8.8.8.8"]).decode()
            m = re.search(r"src (\S+)", out)
            if m:
                return m.group(1)
        except Exception:
            pass
    return None


def is_empty(slot):
    udid = slot.get("udid", "").lower()
    name = slot.get("name", "").lower()
    if not name or name == "xxx":
        return True
    if "x" in udid or re.fullmatch(r"[0-]+", udid):
        return True
    return False


def main():
    parser = argparse.ArgumentParser(description="Onboard a singer's device")
    parser.add_argument("-n", "--name", required=True, help="Singer's name")
    parser.add_argument("-u", "--udid", help="Device UDID (optional)")
    parser.add_argument("-i", "--ip", help="Device IP (optional)")
    args = parser.parse_args()
    name = args.name.strip()
    udid = get_udid(args.udid)
    ip = detect_ip(args.ip)
    if not ip:
        ip = input("Enter device IP address: ").strip()

    project_root = os.path.abspath(os.path.join(os.path.dirname(__file__), os.pardir))
    map_path = os.path.join(project_root, "FlashlightsInTheDark", "flash_ip+udid_map.json")
    with open(map_path, "r+", encoding="utf-8") as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        data = json.load(f)
        slot_key = None
        for key in sorted(data.keys(), key=lambda k: int(k)):
            if is_empty(data[key]):
                slot_key = key
                break
        if not slot_key:
            sys.exit("Error: No available slot found.")
        data[slot_key]["udid"] = udid
        data[slot_key]["name"] = name
        data[slot_key]["ip"] = ip
        f.seek(0)
        json.dump(data, f, indent=2)
        f.truncate()
        fcntl.flock(f, fcntl.LOCK_UN)
    print(f"Assigned slot {slot_key} to {name} ({udid}) at {ip}")
    print("Registering device in Apple Developer Portal...")
    subprocess.run(["fastlane", "register_device", f"udid:{udid}", f"name:{name}"], check=True)
    print("Syncing provisioning profiles...")
    subprocess.run(["fastlane", "sync_code_signing"], check=True)
    print("Onboarding complete.")


if __name__ == "__main__":
    main()