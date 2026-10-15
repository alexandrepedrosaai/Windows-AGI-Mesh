# syntax=docker/dockerfile:1

FROM python:3.12-alpine

LABEL org.opencontainers.image.title="Windows AGI Mesh" \
      org.opencontainers.image.description="Windows AGI Mesh application" \
      org.opencontainers.image.source="https://github.com/alexandrepedrosaai/Windows-AGI-Mesh"

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    APP_HOST=0.0.0.0 \
    APP_PORT=8080

WORKDIR /app

RUN addgroup -S appgroup \
    && adduser -S -D -H -u 10001 -G appgroup appuser

COPY --chown=appuser:appgroup app.py README.md ./

USER appuser

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8080/health', timeout=3)" || exit 1

CMD ["python", "app.py"]
