// Regenerates the shared Swift/web programming-defaults parity fixture.
import { writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { normalizedProgrammingDefaults } from "../tests/programming-defaults-fixture.mjs";

const out = fileURLToPath(new URL("../tests/fixtures/programming-defaults.json", import.meta.url));
writeFileSync(out, JSON.stringify(await normalizedProgrammingDefaults(), null, 2) + "\n");
console.log(`wrote ${out}`);
