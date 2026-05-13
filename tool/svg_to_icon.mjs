// Genera los iconos del launcher a partir de assets/site_visit_icon.svg.
// Requiere: npm install sharp  (una sola vez en tool/)
// Uso: node tool/svg_to_icon.mjs

import { readFileSync } from 'fs';
import sharp from 'sharp';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dir = dirname(fileURLToPath(import.meta.url));
const root  = join(__dir, '..');

const svgRaw     = readFileSync(join(root, 'assets', 'site_visit_icon.svg'), 'utf8');
const svgWhite   = Buffer.from(svgRaw.replaceAll('currentColor', 'white'));

// ── Foreground (1024×1024, icono blanco, fondo transparente) ─────────────────
const transparent = { r: 0, g: 0, b: 0, alpha: 0 };

const fgBuffer = await sharp(svgWhite)
  .resize(800, 800, { fit: 'contain', background: transparent })
  .extend({ top: 112, bottom: 112, left: 112, right: 112, background: transparent })
  .png()
  .toBuffer();

await sharp(fgBuffer).toFile(join(root, 'icon_foreground.png'));
console.log('icon_foreground.png generado (1024×1024, fondo transparente)');

// ── Launcher completo (1024×1024, fondo rojo + icono blanco centrado) ─────────
const red = { r: 255, g: 59, b: 48, alpha: 255 };

const bgBuffer = await sharp({
  create: { width: 1024, height: 1024, channels: 4, background: red },
}).png().toBuffer();

await sharp(bgBuffer)
  .composite([{ input: fgBuffer, blend: 'over' }])
  .png()
  .toFile(join(root, 'icon_launcher.png'));

console.log('icon_launcher.png generado (1024×1024, fondo #FF3B30)');
