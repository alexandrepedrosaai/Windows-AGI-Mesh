# Base image: Ubuntu + .NET + Q#

# Instalar dependências básicas
RUN apt-get update && apt-get install -y \
    curl \
    git \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Diretório de trabalho
WORKDIR /app/WebGPU/Majoran-Starship
WORKDIR /app/WebGPU/Majoran-Starship

# Copiar todos os arquivos para dentro do container
COPY . .

# Compilar o projeto Q#
RUN dotnet build MajoranaStarship.qsproj -c Release

# Runtime image


WORKDIR /app/WebGPU/Majoran-Starship

# Criar usuário e grupo sem privilégios para execução da aplicação
RUN groupadd --system --gid 10001 appgroup && \
    useradd --system --uid 10001 --gid appgroup --create-home --shell /usr/sbin/nologin appuser

# Copiar binários compilados com ownership do usuário não-root
COPY --from=build --chown=appuser:appgroup /app/WebGPU/Majoran-Starship/bin ./bin

# Labels para integração com GitHub Container Registry
LABEL org.opencontainers.image.source="https://github.com/alexandrepedrosaai/Edge-AI-APP"
LABEL org.opencontainers.image.description="Topo-Majorana-Quibits CI CD container para rodar binários Q#"
LABEL org.opencontainers.image.workflow="Topo-Majorana-Quibits CI CD"

# Executar como usuário não-root
USER appuser

# Comando padrão: rodar o projeto Q#
CMD ["dotnet", "bin/Release/net8.0/MajoranaStarship.dll"]
