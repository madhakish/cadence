// Render the production SVG with its actual sprite assets, not a mockup.
// Usage: node tools/render-barbell-proof.mjs /absolute/output/directory [theme,theme,...]
// The optional theme list adds one themed proof per theme (kg set, sprite path); the
// fixture output below never changes with it.
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { JSDOM } from 'jsdom';
import sharp from 'sharp';
import * as C from '../app/js/core.js';
import { barbellScene } from '../app/js/barbell-scene.js';
import { barbellLayout, plateProfile, cameraOrbitPosition, inspectorCamera, inspectorFrame } from '../app/js/barbell-inspector.js';
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
// Optional themed proofs of the sprite path (no fixture output).
for (const theme of (process.argv[3] || '').split(',').filter(Boolean)) {
  const solution = C.enteredPlateSolution(C.BARS.bar20kg, [25, 20, 15, 10, 5, 2.5, 1.25].map((value) => ({ plate: { value, unit: 'kg' }, count: 1 })), 5.5);
  for (const exploded of [false, true]) {
    const stage = B.barbellStage(B.barbellSVG(solution, 'full', 'steel', { plateTheme: theme }), { emphasis: 'expanded' });
    if (!exploded) stage.querySelector('.barbell-explode').click();
    const svg = stage.querySelector('svg.realistic');
    svg.setAttribute('xmlns', 'http://www.w3.org/2000/svg');
    for (const image of svg.querySelectorAll('image')) {
      const bytes = await readFile(fileURLToPath(image.getAttribute('href')));
      image.setAttribute('href', `data:image/png;base64,${bytes.toString('base64')}`);
    }
    await sharp(Buffer.from(svg.outerHTML)).resize({ width: 1280 }).flatten({ background: '#14161a' })
      .png().toFile(`${output}/theme-${theme}-${exploded ? 'exploded' : 'assembled'}-1280.png`);
  }
}
// Intentional generator output consumed by both clients' deterministic tests.
await writeFile(new URL('../tests/fixtures/barbell-scene.json',import.meta.url),JSON.stringify(fixtures,null,2)+'\n');
// The 3D inspector model: one half-exploded layout, the lathe profiles per
// family, and camera positions, pinned for CadenceCore's BarbellInspector.
const inspector = { solution: { bar: fixtures[0].loadout.bar, perSide: fixtures[0].loadout.perSide }, style: 'steel', explode: 0.5 };
inspector.layout = barbellLayout(inspector.solution, inspector.style, inspector.explode);
inspector.profiles = [['bumper', 450, 60], ['steel', 450, 27], ['change', 160, 16], ['ipf', 450, 22.5], ['iron', 450, 50], ['machined', 448, 38]]
  .map(([family, diameter, thickness]) => ({ family, diameter, thickness, points: plateProfile(family, diameter, thickness) }));
inspector.cameras = [{ camera: inspectorCamera(true), distance: 1600 }, { camera: inspectorCamera(false), distance: 1600 },
  { camera: { yaw: 90, pitch: 0, zoom: 2 }, distance: 1000 }, { camera: { yaw: -120, pitch: 60, zoom: 0.7 }, distance: 1000 }]
  .map((c) => ({ ...c, position: cameraOrbitPosition(c.camera, c.distance) }));
inspector.frames = [0, 0.5, 1].map((explode) => ({ explode, frame: inspectorFrame(barbellLayout(inspector.solution, inspector.style, explode), explode) }));
await writeFile(new URL('../tests/fixtures/barbell-3d.json',import.meta.url),JSON.stringify(inspector,null,2)+'\n');
console.log(`Production SVG proofs written to ${output}`);
