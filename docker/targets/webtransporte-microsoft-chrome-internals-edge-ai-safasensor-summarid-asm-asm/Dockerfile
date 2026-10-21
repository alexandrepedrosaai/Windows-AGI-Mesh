# syntax=docker/dockerfile:1.7
FROM python:3.12-slim
ARG SOURCE_PATH=WebTransporte/Microsoft Chrome. (internals)Edge AI/Safasensor.summarid.asm.asm
ENV AGIMESH_SOURCE=/opt/agi-mesh/source/Safasensor.summarid.asm.asm \
    AGIMESH_SOURCE_TYPE=assembly \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1
LABEL org.opencontainers.image.title="Windows AGI Mesh - Safasensor.summarid.asm.asm" \
      org.opencontainers.image.source="https://github.com/alexandrepedrosaai/Windows-AGI-Mesh" \
      org.opencontainers.image.description="Independent source package for WebTransporte/Microsoft Chrome. (internals)Edge AI/Safasensor.summarid.asm.asm" \
      org.opencontainers.image.source-path="WebTransporte/Microsoft Chrome. (internals)Edge AI/Safasensor.summarid.asm.asm"
WORKDIR /opt/agi-mesh
COPY ["WebTransporte/Microsoft Chrome. (internals)Edge AI/Safasensor.summarid.asm.asm", "/opt/agi-mesh/source/Safasensor.summarid.asm.asm"]
COPY docker/entrypoint.sh /usr/local/bin/agimesh-entrypoint
RUN chmod 0555 /usr/local/bin/agimesh-entrypoint && \
    test -s "/opt/agi-mesh/source/Safasensor.summarid.asm.asm"
USER 65532:65532
ENTRYPOINT ["/usr/local/bin/agimesh-entrypoint"]
