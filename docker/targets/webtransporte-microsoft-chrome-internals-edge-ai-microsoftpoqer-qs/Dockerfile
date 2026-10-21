# syntax=docker/dockerfile:1.7
FROM python:3.12-slim
ARG SOURCE_PATH=WebTransporte/Microsoft Chrome. (internals)Edge AI/MicrosoftPoqer.qs
ENV AGIMESH_SOURCE=/opt/agi-mesh/source/MicrosoftPoqer.qs \
    AGIMESH_SOURCE_TYPE=powershell \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1
LABEL org.opencontainers.image.title="Windows AGI Mesh - MicrosoftPoqer.qs" \
      org.opencontainers.image.source="https://github.com/alexandrepedrosaai/Windows-AGI-Mesh" \
      org.opencontainers.image.description="Independent source package for WebTransporte/Microsoft Chrome. (internals)Edge AI/MicrosoftPoqer.qs" \
      org.opencontainers.image.source-path="WebTransporte/Microsoft Chrome. (internals)Edge AI/MicrosoftPoqer.qs"
WORKDIR /opt/agi-mesh
COPY ["WebTransporte/Microsoft Chrome. (internals)Edge AI/MicrosoftPoqer.qs", "/opt/agi-mesh/source/MicrosoftPoqer.qs"]
COPY docker/entrypoint.sh /usr/local/bin/agimesh-entrypoint
RUN chmod 0555 /usr/local/bin/agimesh-entrypoint && \
    test -s "/opt/agi-mesh/source/MicrosoftPoqer.qs"
USER 65532:65532
ENTRYPOINT ["/usr/local/bin/agimesh-entrypoint"]
