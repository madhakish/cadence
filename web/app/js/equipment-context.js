// Original category-context cutouts, never a prescription/loading diagram.
const files = { Main: 'astra/main-context.jpg', Accessory: 'equipment-context/accessory.png', Conditioning: 'equipment-context/conditioning.png' };
export function equipmentContext(category, { width = 96 } = {}) {
  const file = files[category];
  if (!file) return null;
  const image = document.createElement('img');
  image.className = 'equipment-context';
  image.src = new URL(`../assets/${file}`, import.meta.url).href;
  image.alt = ''; // The adjacent category/state text carries the same context.
  image.width = width; image.height = width * 2 / 3;
  image.decoding = 'async';
  return image;
}
