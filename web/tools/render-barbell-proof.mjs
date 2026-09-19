// Render the production SVG with its actual sprite assets, not a mockup.
// Usage: node tools/render-barbell-proof.mjs /absolute/output/directory
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { JSDOM } from 'jsdom';
import sharp from 'sharp';
import * as C from '../app/js/core.js';
import { barbellScene } from '../app/js/barbell-scene.js';
const dom = new JSDOM('<html><body></body></html>');
global.document = dom.window.document;
const B = await import('../app/js/barbell.js');
const output = process.argv[2];
if (!output) throw new Error('Provide an output directory outside source');
await mkdir(output,{recursive:true});
const profiles = [
  ['steel', C.enteredPlateSolution(C.BARS.bar45lb,[45,25,10,2.5].map(value=>({plate:{value,unit:'lb'},count:1})),5)],
  ['bumper', C.enteredPlateSolution(C.BARS.bar20kg,[20,10,5].map(value=>({plate:{value,unit:'kg'},count:1})))],
];
const fixtures=[];
for (const [style,solution] of profiles) for (const exploded of [false,true]) {
  fixtures.push({loadout:{bar:solution.bar,perSide:solution.perSide,collarLb:solution.collarLb},style,exploded,
    scene:barbellScene(solution,style,exploded)});
  const stage=B.barbellStage(B.barbellSVG(solution,'full',style),{emphasis:'expanded'});
  if (!exploded) stage.querySelector('.barbell-explode').click();
  const svg=stage.querySelector('svg.realistic');
  svg.setAttribute('xmlns','http://www.w3.org/2000/svg');
  for (const image of svg.querySelectorAll('image')) {
    const bytes=await readFile(fileURLToPath(image.getAttribute('href')));
    image.setAttribute('href',`data:image/png;base64,${bytes.toString('base64')}`);
  }
  const source=Buffer.from(svg.outerHTML);
  for (const width of [390,1280]) await sharp(source).resize({width}).flatten({background:'#14161a'})
    .png().toFile(`${output}/${style}-${exploded?'exploded':'assembled'}-${width}.png`);
}
// Intentional generator output consumed by both clients' deterministic tests.
await writeFile(new URL('../tests/fixtures/barbell-scene.json',import.meta.url),JSON.stringify(fixtures,null,2)+'\n');
console.log(`Production SVG proofs written to ${output}`);
