"""Create/select a real edge-width device; never substitute a nearby viewport."""
import json
import subprocess
import sys

names = {"375": "iPhone SE (3rd generation)", "430": "iPhone 15 Pro Max"}
name = names[sys.argv[1]]

def simctl(*args):
    return subprocess.check_output(["xcrun", "simctl", *args], text=True).strip()

devices = json.loads(simctl("list", "devices", "available", "-j"))
matches = [d for group in devices["devices"].values() for d in group if d["name"] == name]
if matches:
    print(matches[0]["udid"])
else:
    types = json.loads(simctl("list", "devicetypes", "-j"))["devicetypes"]
    device_type = next(t["identifier"] for t in types if t["name"] == name)
    runtimes = json.loads(simctl("list", "runtimes", "-j"))["runtimes"]
    available = [r for r in runtimes if r.get("isAvailable") and r["name"].startswith("iOS ")]
    runtime = max(available, key=lambda r: tuple(int(n) for n in r["version"].split(".")))
    print(simctl("create", name, device_type, runtime["identifier"]))
