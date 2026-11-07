FROM scratch AS qsharp-build
COPY Dockerfile /BUILD_DISABLED_QSHARP.txt

FROM scratch AS neural-build
COPY Dockerfile /BUILD_DISABLED_NEURAL.txt

FROM mcr.microsoft.com/dotnet/runtime:9.0 AS runtime
WORKDIR /app/zenithui
CMD ["sh", "-c", "echo 'ZenithUI base image: no application DLLs; compilation disabled.'"]
