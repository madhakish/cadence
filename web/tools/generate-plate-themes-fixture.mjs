// Regenerates web/tests/fixtures/plate-themes.json — the shared,
// language-neutral snapshot of the plate theme model. Both suites assert their
// copy against it (node: plate-themes.test.mjs; Swift: PlateThemeTests), so
// JS↔Swift drift fails CI on whichever side forgot the mirror. Run after
// editing plate-theme.js AND PlateTheme.swift:
//   node web/tools/generate-plate-themes-fixture.mjs
import { writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { normalizedPlateThemes } from "../tests/plate-themes-fixture.mjs";

const out = fileURLToPath(new URL("../tests/fixtures/plate-themes.json", import.meta.url));
writeFileSync(out, JSON.stringify(normalizedPlateThemes(), null, 2) + "\n");
console.log(`wrote ${out}`);
