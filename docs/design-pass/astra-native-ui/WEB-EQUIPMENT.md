# Astra equipment in the PWA

Today, session rows, exercise details and both plate calculator modes use the same photographic compositor. It reads the solved or hand-entered load in its original order. Each disc has a photographed face, sidewall and metal insert whose dimensions follow the selected equipment profile. The near sleeve inspection separates those same pieces and captions each one with its exact value and unit.

The assembled camera follows the bore centers, bar ends and near-to-far diameter change in the 1672 × 941 oak and blue bumper study. The empty stage contains the gym, platform and engraving. The equipment layers supply the selected shaft, sleeves, shoulders, endcap and any configured collars. Calibrated steel uses the walnut stage, black banded bumpers use white oak, IWF training uses maple, and the remaining themes use oak. [Astra study 03](../astra-2026-11-01/03-platform-oak-blue.png)

The circular plate keys and bar graphics share their face photographs. The Cadence imprint and the 45 lb, 20 kg and 15 kg stamps come from the artwork. Other denominations are typeset from the plate record. Each complete bar has a readable sleeve order and individually named plates. The exploded view keeps screen-size captions and scrolls horizontally for long stacks.

Run `python3 web/tools/export-astra-equipment.py` from the repository to copy the native photographs into the PWA. The service worker precaches them on first install. From `web/`, `npm test` checks asset identity, physical geometry and labels. `npm run test:browser` exercises the installed offline app in Chromium and WebKit and captures the assembled and exploded mixed-unit load.
