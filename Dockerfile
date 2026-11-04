# ZenithUI container: Q# runtime plus the VA Q-learning neural workload.

FROM mcr.microsoft.com/dotnet/sdk:9.0 AS qsharp-build
WORKDIR /src
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
