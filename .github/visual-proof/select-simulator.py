"""Choose the exact 402 × 874 pt device used by the recorded DP-1 captures."""
import json
import subprocess

payload = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"], text=True))
phones = [device for runtime in payload["devices"].values() for device in runtime
          if device["name"] == "iPhone 17 Pro"]
if not phones:
    raise SystemExit("DP-1 proof requires the recorded iPhone 17 Pro simulator")
print(phones[0]["udid"])
