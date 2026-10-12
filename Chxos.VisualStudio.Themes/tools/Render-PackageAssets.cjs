// Editable SVG sources are authoritative. Install locked dependencies with npm ci.
// Usage from the project directory: npm run assets:check | npm run assets:render
const fs = require('node:fs');
const path = require('node:path');
const sharp = require('sharp');
const project = path.resolve(__dirname, '..');
const catalog = JSON.parse(fs.readFileSync(path.join(project, 'authoring/PackageCatalog.json'), 'utf8'));
(async () => {
  for (const pkg of catalog.Packages) {
    for (const asset of [pkg.Icon, pkg.PreviewImage]) {
      const output = path.join(project, asset);
      const source = output.replace(/\.png$/, '.svg');
      const png = await sharp(source).png().toBuffer();
      if (process.argv.includes('--check')) {
        if (!fs.existsSync(output) || !png.equals(fs.readFileSync(output))) throw new Error(`Asset drift: ${asset}`);
      } else fs.writeFileSync(output, png);
    }
  }
  console.log('Package assets rendered/checked for all catalog packages.');
})().catch(error => { console.error(error.message); process.exitCode = 1; });
