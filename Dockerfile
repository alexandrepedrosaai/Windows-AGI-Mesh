FROM scratch AS qsharp-build
COPY Dockerfile /BUILD_DISABLED_QSHARP.txt

FROM scratch AS neural-build
COPY Dockerfile /BUILD_DISABLED_NEURAL.txt

FROM mcr.microsoft.com/dotnet/runtime:9.0 AS runtime
LABEL org.opencontainers.image.title="zenithui" \
      org.opencontainers.image.source="https://github.com/alexandrepedrosaai/Windows-AGI-Mesh" \
      org.opencontainers.image.description="ZenithUI base runtime image; no compiled application or Q# workload" \
      org.opencontainers.image.workflow="CI-CD 03 ZenithUI Docker Build Push"
WORKDIR /app/zenithui
CMD ["sh", "-c", "echo 'ZenithUI base image: no application DLLs; compilation disabled.'"]
