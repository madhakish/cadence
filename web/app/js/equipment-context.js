// Original category-context cutouts, never a prescription/loading diagram.
const files = { Main: 'main', Accessory: 'accessory', Conditioning: 'conditioning' };
export function equipmentContext(category, { width = 96 } = {}) {
  const file = files[category];
  if (!file) return null;
  const image = document.createElement('img');
  image.className = 'equipment-context';
  image.src = new URL(`../assets/equipment-context/${file}.png`, import.meta.url).href;
  image.alt = ''; // The adjacent category/state text carries the same context.
  image.width = width; image.height = width * 2 / 3;
  image.decoding = 'async';
  return image;
}
