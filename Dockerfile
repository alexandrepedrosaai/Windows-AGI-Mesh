# ZenithUI container: Q# runtime plus the VA Q-learning neural workload.

FROM mcr.microsoft.com/dotnet/sdk:9.0 AS qsharp-build
WORKDIR /src

# Microsoft.Quantum.Sdk/0.28 launches a net6.0 build helper. Keep the
# repository-required SDK 9 and add the compatible .NET 6 runtime alongside it.
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh \
    && bash /tmp/dotnet-install.sh \
        --runtime dotnet \
        --version 6.0.36 \
        --install-dir /usr/share/dotnet \
        --skip-non-versioned-files \
    && rm /tmp/dotnet-install.sh

COPY . .

# MajoranaStarship.qsproj uses Microsoft.Quantum.Sdk/0.28 and targets net8.0.
RUN dotnet publish MajoranaStarship.qsproj \
    --configuration Release \
    --output /out/qsharp \
    --nologo

FROM mcr.microsoft.com/dotnet/sdk:9.0 AS neural-build
WORKDIR /src/quantum/VAQLearningNeural
COPY quantum/VAQLearningNeural/VAQLearningNeural.csproj .
COPY quantum/VAQLearningNeural/Program.cs .

RUN dotnet publish VAQLearningNeural.csproj \
    --configuration Release \
    --output /out/neural \
    --nologo

FROM mcr.microsoft.com/dotnet/runtime:9.0 AS runtime
WORKDIR /app/zenithui

COPY --from=qsharp-build /out/qsharp/ ./
COPY --from=neural-build /out/neural/ /opt/vaql/

LABEL org.opencontainers.image.title="zenithui"
LABEL org.opencontainers.image.source="https://github.com/alexandrepedrosaai/Windows-AGI-Mesh"
LABEL org.opencontainers.image.description="ZenithUI Q# runtime with VA Q-learning neural polymorphic reconstruction"
LABEL org.opencontainers.image.workflow="CI-CD 03 ZenithUI Docker Build Push"

# The default command runs the Q# ZenithUI workload.
CMD ["dotnet", "MajoranaStarship.dll"]
