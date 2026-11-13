'use strict';

const assert = require('node:assert/strict');
const sdk = require('./index.js');

const client = sdk.createClient();
const entries = client.manifest();
assert.ok(entries.length > 0, 'SDK package must contain files');
assert.match(client.digest(), /^[a-f0-9]{64}$/, 'SDK digest must be SHA-256');
assert.ok(entries.some((entry) => entry.path === 'package.json'), 'package.json must be packaged');
console.log(JSON.stringify({ files: entries.length, digest: client.digest() }, null, 2));
