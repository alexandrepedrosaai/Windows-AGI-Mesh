# syntax=docker/dockerfile:1.7
FROM python:3.12-slim
ARG SOURCE_PATH=modules/DeepSpace.qs
ENV AGIMESH_SOURCE=/opt/agi-mesh/source/DeepSpace.qs \
    AGIMESH_SOURCE_TYPE=quantum-source \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1
LABEL org.opencontainers.image.title="Windows AGI Mesh - DeepSpace.qs" \
      org.opencontainers.image.source="https://github.com/alexandrepedrosaai/Windows-AGI-Mesh" \
      org.opencontainers.image.description="Independent source package for modules/DeepSpace.qs" \
      org.opencontainers.image.source-path="modules/DeepSpace.qs"
WORKDIR /opt/agi-mesh
COPY ["modules/DeepSpace.qs", "/opt/agi-mesh/source/DeepSpace.qs"]
COPY docker/entrypoint.sh /usr/local/bin/agimesh-entrypoint
RUN chmod 0555 /usr/local/bin/agimesh-entrypoint && \
    test -s "/opt/agi-mesh/source/DeepSpace.qs"
USER 65532:65532
ENTRYPOINT ["/usr/local/bin/agimesh-entrypoint"]
