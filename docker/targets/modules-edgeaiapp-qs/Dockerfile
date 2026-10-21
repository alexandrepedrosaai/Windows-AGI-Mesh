# syntax=docker/dockerfile:1.7
FROM python:3.12-slim
ARG SOURCE_PATH=modules/EdgeAIApp.qs
ENV AGIMESH_SOURCE=/opt/agi-mesh/source/EdgeAIApp.qs \
    AGIMESH_SOURCE_TYPE=quantum-source \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1
LABEL org.opencontainers.image.title="Windows AGI Mesh - EdgeAIApp.qs" \
      org.opencontainers.image.source="https://github.com/alexandrepedrosaai/Windows-AGI-Mesh" \
      org.opencontainers.image.description="Independent source package for modules/EdgeAIApp.qs" \
      org.opencontainers.image.source-path="modules/EdgeAIApp.qs"
WORKDIR /opt/agi-mesh
COPY ["modules/EdgeAIApp.qs", "/opt/agi-mesh/source/EdgeAIApp.qs"]
COPY docker/entrypoint.sh /usr/local/bin/agimesh-entrypoint
RUN chmod 0555 /usr/local/bin/agimesh-entrypoint && \
    test -s "/opt/agi-mesh/source/EdgeAIApp.qs"
USER 65532:65532
ENTRYPOINT ["/usr/local/bin/agimesh-entrypoint"]
