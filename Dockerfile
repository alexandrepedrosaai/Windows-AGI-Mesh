# syntax=docker/dockerfile:1

FROM alpine:3.20

LABEL org.opencontainers.image.title="Windows AGI Mesh" \
      org.opencontainers.image.description="Containerized Windows AGI Mesh repository documentation and release artifact" \
      org.opencontainers.image.source="https://github.com/alexandrepedrosaai/Windows-AGI-Mesh" \
      org.opencontainers.image.licenses="MIT"

RUN apk add --no-cache ca-certificates \
    && mkdir -p /srv/www \
    && chown -R 65534:65534 /srv/www

COPY --chown=65534:65534 README.md /srv/www/index.html

USER 65534:65534

WORKDIR /srv/www

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD wget --quiet --spider http://127.0.0.1:8080/ || exit 1

ENTRYPOINT ["/bin/sh", "-c"]
CMD ["exec busybox httpd -f -p 8080 -h /srv/www"]
