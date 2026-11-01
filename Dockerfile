# Base image: Ubuntu + .NET + Q#
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build

# Instalar dependências básicas
RUN apt-get update && apt-get install -y \
    curl \
    git \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Usar o SDK já presente na imagem base mcr.microsoft.com/dotnet/sdk:8.0
# (evita baixar e executar script remoto sem verificação de integridade)

# Diretório de trabalho
WORKDIR /app/WebGPU/Majoran-Starship

# Copiar todos os arquivos para dentro do container
COPY . .

# Compilar o projeto Q#
RUN dotnet build MajoranaStarship.qsproj -c Release

# Runtime image
FROM mcr.microsoft.com/dotnet/runtime:8.0 AS runtime

WORKDIR /app/WebGPU/Majoran-Starship

# Criar usuário não-root para execução
RUN groupadd --gid 10001 appuser && useradd --uid 10001 --gid appuser --create-home --shell /usr/sbin/nologin appuser

# Copiar binários compilados com permissões para o usuário da aplicação
COPY --from=build --chown=appuser:appuser /app/WebGPU/Majoran-Starship/bin ./bin

# Labels para integração com GitHub Container Registry
LABEL org.opencontainers.image.source="https://github.com/alexandrepedrosaai/Edge-AI-APP"
LABEL org.opencontainers.image.description="Topo-Majorana-Quibits CI CD container para rodar binários Q#"
LABEL org.opencontainers.image.workflow="Topo-Majorana-Quibits CI CD"

# Executar como usuário não-root
USER appuser

# Comando padrão: rodar o projeto Q#
CMD ["dotnet", "run", "--project", "MajoranaStarship.qsproj", "-c", "Release"]
