import { cp, mkdir, readFile, readdir, rm, writeFile } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';

const root = dirname(fileURLToPath(import.meta.url));
const source = join(root, 'src');
const output = resolve(root, 'dist');
if (output !== join(root, 'dist')) throw new Error('Unexpected output directory');
await mkdir(source, { recursive: true });
await rm(output, { recursive: true, force: true });
await cp(source, output, { recursive: true });
const files = [];
async function walk(folder, prefix = '') {
  for (const entry of await readdir(folder, { withFileTypes: true })) {
    const name = prefix + entry.name;
    if (entry.isDirectory()) await walk(join(folder, entry.name), name + '/');
    else {
      const bytes = await readFile(join(folder, entry.name));
      files.push({ file: name, bytes: bytes.length, sha256: createHash('sha256').update(bytes).digest('hex') });
    }
  }
}
await walk(output);
await writeFile(join(root, 'build-manifest.json'), JSON.stringify({ version: '1.0.0', files }, null, 2) + '\n');
console.log(`Built ${files.length} local files (${files.reduce((n, f) => n + f.bytes, 0).toLocaleString()} bytes) → dist/`);
