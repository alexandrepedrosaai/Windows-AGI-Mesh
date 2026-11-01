# MajoranaZenithSDK NuGet catalog

This directory defines a deterministic catalog of 50 NuGet packages.

1. `MajoranaZenithSDK` is always package 1 and is published first.
2. Packages 2–50 use the first 49 sorted `.csproj`/`.qsproj` files in the repository as their source names.
3. Every package after `MajoranaZenithSDK` declares a dependency on the exact CI version of `MajoranaZenithSDK`.
4. The workflow generates the package projects, packs the SDK first, publishes it to GitHub Packages, then restores and publishes the remaining 49 packages.
5. Each `.nupkg` receives a companion `.sha256` file. These are integrity hashes, not encryption.

The workflow uses only the built-in `GITHUB_TOKEN` supplied by GitHub Actions. It publishes to the repository's GitHub Packages NuGet feed and creates/updates a commit-specific GitHub Release on every push to `main`.

To consume the packages locally, configure the GitHub Packages NuGet source and authenticate with a token that has package read access:

```text
https://nuget.pkg.github.com/alexandrepedrosaai/index.json
```
