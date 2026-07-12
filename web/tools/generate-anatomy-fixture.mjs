// Regenerates web/tests/fixtures/anatomy.json — the shared snapshot of the
// muscle map + figure geometry. Both suites assert their copy against it
// (node: smoke.test.mjs; Swift: AnatomyDataTests), so JS↔Swift drift fails CI.
// Run after editing anatomy.js AND AnatomyData.swift:
//   node web/tools/generate-anatomy-fixture.mjs
import { writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { normalizedAnatomy } from "../tests/anatomy-fixture.mjs";

const out = fileURLToPath(new URL("../tests/fixtures/anatomy.json", import.meta.url));
writeFileSync(out, JSON.stringify(await normalizedAnatomy(), null, 2) + "\n");
console.log(`wrote ${out}`);
