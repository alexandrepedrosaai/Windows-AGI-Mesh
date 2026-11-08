# =============================================================================
# Windows AGI Benchmark Lab — Benchmark Runner Dockerfile
# Copyright (c) 2026 Microsoft Corporation. All Rights Reserved.
# =============================================================================

FROM python:3.12-slim AS base

LABEL maintainer="Microsoft Corporation <agi-bench@microsoft.com>"
LABEL com.microsoft.project="windows-agi-benchmark"
LABEL com.microsoft.component="benchmark-runner"
LABEL com.microsoft.version="1.0.0"
LABEL com.microsoft.license="exclusive"

# Build arguments
ARG DEBIAN_FRONTEND=noninteractive
ARG BUILD_DATE
ARG VCS_REF
ARG VERSION=1.0.0

LABEL org.opencontainers.image.created="${BUILD_DATE}"
LABEL org.opencontainers.image.revision="${VCS_REF}"
LABEL org.opencontainers.image.version="${VERSION}"
LABEL org.opencontainers.image.title="AGI Benchmark Runner"
LABEL org.opencontainers.image.vendor="Microsoft Corporation"

# =============================================================================
# System dependencies
# =============================================================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    curl \
    wget \
    git \
    jq \
    ca-certificates \
    libssl-dev \
    libffi-dev \
    libgomp1 \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    libgl1-mesa-glx \
    sysbench \
    fio \
    iperf3 \
    htop \
    procps \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# =============================================================================
# Python environment
# =============================================================================
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONPATH=/app

WORKDIR /app

# Install Python dependencies in layers for cache efficiency
COPY pyproject.toml ./

# Core dependencies
RUN pip install --upgrade pip setuptools wheel && \
    pip install \
        requests \
        httpx \
        aiohttp \
        pydantic \
        pydantic-settings \
        typer \
        rich \
        loguru \
        pyyaml \
        toml \
        tqdm \
        click

# Data & visualization
RUN pip install \
        pandas \
        numpy \
        matplotlib \
        seaborn \
        plotly \
        kaleido

# Monitoring & metrics
RUN pip install \
        prometheus-client \
        psutil \
        py-cpuinfo

# AI/ML clients
RUN pip install \
        openai \
        anthropic \
        transformers \
        accelerate \
        onnxruntime \
        langchain \
        langchain-community

# Vector & cache
RUN pip install \
        qdrant-client \
        redis \
        celery

# Azure SDK
RUN pip install \
        azure-ai-ml \
        azure-identity \
        azure-storage-blob \
        azure-monitor-opentelemetry

# =============================================================================
# Application code
# =============================================================================
COPY benchmark/ ./benchmark/
COPY collectors/ ./collectors/
COPY agents/ ./agents/

# Create reports directory
RUN mkdir -p /app/reports /app/data /app/logs

# =============================================================================
# Runtime configuration
# =============================================================================
ENV REPORT_DIR=/app/reports \
    LOG_DIR=/app/logs \
    DATA_DIR=/app/data \
    OLLAMA_URL=http://ollama:11434 \
    REDIS_URL=redis://redis:6379 \
    QDRANT_URL=http://qdrant:6333 \
    EXPORT_CSV=true \
    EXPORT_JSON=true \
    GENERATE_CHARTS=true \
    LOG_LEVEL=INFO

VOLUME ["/app/reports", "/app/data", "/app/logs"]

HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
    CMD python -c "import benchmark.runner; print('OK')" || exit 1

ENTRYPOINT ["python", "-m", "benchmark.runner"]
CMD ["--help"]
