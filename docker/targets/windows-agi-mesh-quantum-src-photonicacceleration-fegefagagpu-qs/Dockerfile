# syntax=docker/dockerfile:1.7
FROM python:3.12-slim
ARG SOURCE_PATH=Windows-AGI-Mesh-Quantum/src/PhotonicAcceleration/FEGEFAGAGPU.qs
ENV AGIMESH_SOURCE=/opt/agi-mesh/source/FEGEFAGAGPU.qs \
    AGIMESH_SOURCE_TYPE=quantum-source \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1
LABEL org.opencontainers.image.title="Windows AGI Mesh - FEGEFAGAGPU.qs" \
      org.opencontainers.image.source="https://github.com/alexandrepedrosaai/Windows-AGI-Mesh" \
      org.opencontainers.image.description="Independent source package for Windows-AGI-Mesh-Quantum/src/PhotonicAcceleration/FEGEFAGAGPU.qs" \
      org.opencontainers.image.source-path="Windows-AGI-Mesh-Quantum/src/PhotonicAcceleration/FEGEFAGAGPU.qs"
WORKDIR /opt/agi-mesh
COPY ["Windows-AGI-Mesh-Quantum/src/PhotonicAcceleration/FEGEFAGAGPU.qs", "/opt/agi-mesh/source/FEGEFAGAGPU.qs"]
COPY docker/entrypoint.sh /usr/local/bin/agimesh-entrypoint
RUN chmod 0555 /usr/local/bin/agimesh-entrypoint && \
    test -s "/opt/agi-mesh/source/FEGEFAGAGPU.qs"
USER 65532:65532
ENTRYPOINT ["/usr/local/bin/agimesh-entrypoint"]
