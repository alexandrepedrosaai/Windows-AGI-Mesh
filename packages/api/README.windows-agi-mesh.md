# Cumulus Iceberg API integration

This directory contains the runtime components adapted from the public
`alexandrepedrosaai/cumulus` repository at commit
`ac3723879c40bc5067f3cc9ce8426243bcf21e15`.

The integration keeps the Iceberg API server, its endpoint modules, shared
runtime helpers, and model modules. The Dockerfile is adapted for this
repository's standalone layout: it installs the published Cumulus runtime
packages rather than requiring the complete Cumulus monorepo workspace.

The copied source remains under the Apache License 2.0. See
`CUMULUS-LICENSE` for the upstream license text.
