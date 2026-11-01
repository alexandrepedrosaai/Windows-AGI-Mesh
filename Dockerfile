# Base image: Ubuntu + .NET + Q#


# Instalar dependências básicas
RUN apt-get update && apt-get install -y \
    curl \
    git \
    wget \
    && rm -rf /var/lib/apt/lists/*


