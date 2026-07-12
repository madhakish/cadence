// Regenerates web/tests/fixtures/program-templates.json — the shared,
// language-neutral snapshot of the program style templates. Both test suites
// assert their copy of the data against it (node: smoke.test.mjs; Swift:
// ProgramTemplateDataTests), so JS↔Swift drift fails CI on whichever side
// forgot the mirror. Run after editing templates.js AND ProgramTemplateData:
//   node web/tools/generate-template-fixture.mjs
import { writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { normalizedTemplates } from "../tests/template-fixture.mjs";

const out = fileURLToPath(new URL("../tests/fixtures/program-templates.json", import.meta.url));
writeFileSync(out, JSON.stringify(await normalizedTemplates(), null, 2) + "\n");
console.log(`wrote ${out}`);
