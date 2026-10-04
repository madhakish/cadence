"""Install the recorded, DEBUG-only proof harness into exact DP-1 source.

No styling, geometry, solver, or stored schema is patched. The calculator's
initial input is the fixture value; all later actions use its real controls.
"""
import shutil
import subprocess
import sys
from pathlib import Path

proof, baseline = map(lambda p: Path(p).resolve(), sys.argv[1:])
expected = "11895fb95cde9e4b938831098d00dd0350b45bc2"
actual = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=baseline, text=True).strip()
if actual != expected:
    raise SystemExit(f"Baseline source differs: {actual}")
harness = proof / ".github/visual-proof"
target = baseline / "CadenceBaselineVisualProofUITests"
target.mkdir()
shutil.copyfile(harness / "BaselineVisualProofUITests.swift", target / "VisualProofUITests.swift")
shutil.copyfile(proof / "CadenceVisualProofUITests/CalculatorProofCases.swift", target / "CalculatorProofCases.swift")
seed = (harness / "LegacyVisualProofSeed.swift").read_text()
seed = seed.replace("                    cordVolume: 0.42\n"
                    "                ),\n                enteredUnit: .kg\n",
                    "                    cordVolume: 0.42\n                )\n")
(baseline / "Cadence/Seed/VisualProofSeed.swift").write_text(seed)
subprocess.run(["git", "apply", str(harness / "baseline-instrumentation.patch")], cwd=baseline, check=True)
# Record the only tracked source differences for inspection with the artifact.
subprocess.run(["git", "diff", "--exit-code", "--", "CadenceCore", "Cadence/Models",
                "Cadence/Services", "Cadence/Views/AnatomyFigureView.swift",
                "Cadence/Views/BarbellView.swift", "Cadence/Views/LibraryView.swift",
                "Cadence/Views/ActiveSessionView.swift", "Cadence/Views/SettingsView.swift"],
               cwd=baseline, check=True)
print(f"Installed proof-only instrumentation into {actual}")
