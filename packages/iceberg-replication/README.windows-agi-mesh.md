# Iceberg replication workload

This directory is adapted from the public `alexandrepedrosaai/cumulus`
repository at commit `ac3723879c40bc5067f3cc9ce8426243bcf21e15`.

It contains the bootstrap image sources for the Iceberg replication workload:
Java CDC helper code, Python Iceberg/Kafka scripts, Bash orchestration, and
Kafka Connect resource templates. The Docker build is intentionally scoped to
this directory so every `COPY` source is present in the Windows-AGI-Mesh
checkout.

The copied upstream source remains under the Apache License 2.0. See
`CUMULUS-LICENSE` for the complete license text.
