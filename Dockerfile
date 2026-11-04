# ZenithUI base container with build-stage placeholders only.
# The qsharp-build and neural-build targets exist for workflow compatibility;
# they intentionally do not compile code or produce application DLLs.

FROM scratch AS qsharp-build
LABEL org.opencontainers.image.title="zenithui-qsharp-build-placeholder"
LABEL org.opencontainers.image.description="Q# build disabled; no SDK, source compilation, or DLL output"
COPY Dockerfile /BUILD_DISABLED_QSHARP.txt

FROM scratch AS neural-build
LABEL org.opencontainers.image.title="zenithui-neural-build-placeholder"
LABEL org.opencontainers.image.description="Neural build disabled; no SDK, source compilation, or DLL output"
COPY Dockerfile /BUILD_DISABLED_NEURAL.txt

FROM mcr.microsoft.com/dotnet/runtime:9.0 AS runtime

WORKDIR /app/zenithui

LABEL org.opencontainers.image.title="zenithui"
LABEL org.opencontainers.image.source="https://github.com/alexandrepedrosaai/Windows-AGI-Mesh"
LABEL org.opencontainers.image.description="ZenithUI base runtime image; no compiled application or Q# workload"
LABEL org.opencontainers.image.workflow="CI-CD 03 ZenithUI Docker Build Push"

# No application DLL is included. The container prints this notice and exits.
CMD ["sh", "-c", "echo 'ZenithUI base image: no application DLLs; compilation disabled.'"]
