// Convierte favicon.svg a icon.png (1024x1024) usando sharp.
// Requiere: npm install sharp  (una sola vez)
// Uso: node tool/svg_to_icon.mjs

import { readFileSync } from 'fs';
import sharp from 'sharp';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dir = dirname(fileURLToPath(import.meta.url));
const root  = join(__dir, '..');

const svg = readFileSync(join(root, 'favicon.svg'));

await sharp(svg)
  .resize(1024, 1024)
  .png()
  .toFile(join(root, 'icon.png'));

console.log('icon.png generado (1024x1024)');
