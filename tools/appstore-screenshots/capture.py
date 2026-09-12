#!/usr/bin/env python3
"""Captures the raw simulator screenshots the App Store listing is built from.

An iPhone 14 Plus is the only device left in the Xcode 26 simulator set whose
native framebuffer is 1284 x 2778 — App Store Connect's 6.5" slot — so the
captures need no resampling and stay pixel-exact.

The app is filled by `ScreenshotFixtures` (DEBUG-only) rather than by signing
anyone in: a published screenshot of the member card would otherwise carry a
real name, school email and live QR payload.

    python3 tools/appstore-screenshots/capture.py
"""
import json
import os
import subprocess
import time

DEVICE_TYPE = "com.apple.CoreSimulator.SimDeviceType.iPhone-14-Plus"
SIM_NAME = "ASC 6.5"
BUNDLE_ID = "tw.stsa.memberapp"
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "raw_zh")

# Seconds to let each screen settle. 活動 gets longer: it loads live from the
# Indico public category export, and a capture that beats the response
# photographs a spinner.
SCREENS = [("home", 6), ("card", 7), ("events", 12), ("deals", 6), ("profile", 6)]


def simulator():
    """UDID of the capture device, created on first run."""
    devices = json.loads(subprocess.run(
        ["xcrun", "simctl", "list", "devices", "--json"],
        capture_output=True, text=True, check=True).stdout)["devices"]
    for runtime, entries in devices.items():
        if "iOS" not in runtime:
            continue
        for device in entries:
            if device["name"] == SIM_NAME:
                return device["udid"]
    runtime = max(r for r in devices if "iOS" in r)
    return subprocess.run(["xcrun", "simctl", "create", SIM_NAME, DEVICE_TYPE, runtime],
                          capture_output=True, text=True, check=True).stdout.strip()


def main():
    os.makedirs(OUT, exist_ok=True)
    sim = simulator()

    subprocess.run(["xcrun", "simctl", "boot", sim], check=False, capture_output=True)
    subprocess.run(["xcrun", "simctl", "bootstatus", sim, "-b"], check=True, capture_output=True)
    subprocess.run(["xcrun", "simctl", "status_bar", sim, "override",
                    "--time", "9:41", "--batteryState", "charged", "--batteryLevel", "100",
                    "--cellularMode", "active", "--cellularBars", "4",
                    "--wifiMode", "active", "--wifiBars", "3"], check=False)

    for name, wait in SCREENS:
        env = dict(os.environ,
                   SIMCTL_CHILD_STSA_SCREENSHOT="1",
                   SIMCTL_CHILD_STSA_SCREENSHOT_SCREEN=name)
        # Relaunching per screen rather than tapping through: every rerun then
        # lands on the same pixels, and no UI automation has to be kept working.
        subprocess.run(["xcrun", "simctl", "launch", "--terminate-running-process", sim, BUNDLE_ID,
                        "-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_Hant_TW"],
                       env=env, check=True, capture_output=True)
        time.sleep(wait)
        subprocess.run(["xcrun", "simctl", "io", sim, "screenshot", os.path.join(OUT, f"{name}.png")],
                       check=True, capture_output=True)
        print(f"captured {name}")


if __name__ == "__main__":
    main()
