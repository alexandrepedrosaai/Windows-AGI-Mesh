'use strict';

const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');

const SDK_ROOT = path.resolve(__dirname, '..');

function walkFiles(directory) {
  const entries = fs.readdirSync(directory, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name));
  const files = [];
  for (const entry of entries) {
    if (entry.name === 'node_modules' || entry.name === '.git') continue;
    const absolute = path.join(directory, entry.name);
    if (entry.isDirectory()) files.push(...walkFiles(absolute));
    else if (entry.isFile()) files.push(absolute);
  }
  return files;
}

function manifest(root = SDK_ROOT) {
  return walkFiles(root)
    .map((absolute) => {
      const relative = path.relative(root, absolute).split(path.sep).join('/');
      const digest = crypto.createHash('sha256').update(fs.readFileSync(absolute)).digest('hex');
      return { path: relative, sha256: digest, bytes: fs.statSync(absolute).size };
    });
}

function digest(root = SDK_ROOT) {
  const lines = manifest(root).map((item) => `${item.sha256}  ${item.path}`);
  return crypto.createHash('sha256').update(`${lines.join('\n')}\n`).digest('hex');
}

function createClient(options = {}) {
  const root = options.root ? path.resolve(options.root) : SDK_ROOT;
  return {
    root,
    manifest: () => manifest(root),
    digest: () => digest(root),
    resolve: (relativePath) => path.resolve(root, relativePath)
  };
}

module.exports = {
  SDK_ROOT,
  createClient,
  digest,
  manifest
};
