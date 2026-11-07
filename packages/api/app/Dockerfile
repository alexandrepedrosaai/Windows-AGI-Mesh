# Adapted from the Cumulus Iceberg API container.
# The Windows-AGI-Mesh integration is intentionally standalone and does not
# replace the repository's root Node/.NET package metadata.
FROM node:22-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    make \
    g++ \
    git \
    bash \
    ca-certificates \
    openssl \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd --gid 433 task && \
    useradd --uid 431 --gid task --create-home task

WORKDIR /app

# Install the published Cumulus API runtime dependencies from its package
# manifest. The source tree below is the minimal runtime tree used by the
# Iceberg server and does not require the Cumulus workspace root.
COPY packages/api/package.json ./package.json
RUN npm install --omit=dev --ignore-scripts --no-audit --no-fund

COPY packages/api/app ./app
COPY packages/api/endpoints ./endpoints
COPY packages/api/lib ./lib
COPY packages/api/models ./models
COPY packages/api/CUMULUS-LICENSE ./CUMULUS-LICENSE

RUN mkdir -p /app/.duckdb_extensions && \
    chown -R task:task /app
ENV DUCKDB_EXTENSION_DIRECTORY=/app/.duckdb_extensions

USER task
WORKDIR /app
EXPOSE 5001
ENV NODE_ENV=production

CMD ["node", "app/iceberg-index.js"]
