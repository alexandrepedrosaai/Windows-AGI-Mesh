# AzureQuantumSDK

`@alexandrepedrosaai/azurequantumsdk` packages the Azure Quantum assets used by Windows-AGI-Mesh. The package contains the Q# sources, Python modules, configuration, model metadata, documentation, and a small Node.js implementation for deterministic file manifests.

## Install

```bash
npm install @alexandrepedrosaai/azurequantumsdk --registry=https://npm.pkg.github.com
```

The package is published to GitHub Packages' npm registry. Authentication is required for private or organization-scoped package access.

## Use the manifest API

```js
const { createClient } = require('@alexandrepedrosaai/azurequantumsdk');

const sdk = createClient();
console.log(sdk.manifest());
console.log(sdk.digest());
```

`manifest()` returns the normalized relative path, byte count, and SHA-256 digest for every packaged file. `digest()` returns a SHA-256 digest over the canonical manifest. The release workflow computes a second digest over the complete `Azure/` source archive and publishes both manifests with every commit on `main`.

## Repository workflow

The `AzureQuantumSDK` GitHub Actions workflow validates every tracked file under `Azure` in a build matrix. Each matrix job creates and installs the npm package from its own local tarball, archives the complete Azure tree, generates SHA-256 manifests, and uploads the resulting artifacts. A final GitHub Actions deployment job publishes the package and creates a draft release, uploads all matrix artifacts, and then makes the release public.
