# ZenithUI base container — no application build and no DLLs.
FROM mcr.microsoft.com/dotnet/runtime:9.0

WORKDIR /app/zenithui

LABEL org.opencontainers.image.title="zenithui"
LABEL org.opencontainers.image.source="https://github.com/alexandrepedrosaai/Windows-AGI-Mesh"
LABEL org.opencontainers.image.description="ZenithUI base runtime image; no compiled application or Q# workload"
LABEL org.opencontainers.image.workflow="CI-CD 03 ZenithUI Docker Build Push"

# No application DLL is included. The container prints this notice and exits.
CMD ["sh", "-c", "echo 'ZenithUI base image: no application DLLs; compilation disabled.'"]
