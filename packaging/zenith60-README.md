# Zenith 60-module NuGet catalog

This catalog adds 60 named Zenith modules around the `MajoranaZenithSDK` root package.

- Group A contains 20 dependent modules. Each depends on `MajoranaZenithSDK`.
- Group B contains 20 co-dependent modules. Each depends on `MajoranaZenithSDK` plus exactly 19 of the 20 Group A modules. The omitted Group A module rotates deterministically, so all 20 combinations are covered once.
- Group C contains 20 independent modules. They have no NuGet package dependencies and publish themselves after Groups A and B.

The workflow publishes 61 packages total per run: the root package plus the 60 modules. It publishes in dependency order, generates `.sha256` files and `SHA256SUMS.txt`, uploads artifacts, and creates or updates a commit-specific GitHub Release as `github-actions[bot]`.

SHA256 is an integrity hash and is not encryption. The workflow uses the built-in `GITHUB_TOKEN`; no custom token or secret is required.
