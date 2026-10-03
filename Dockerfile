# syntax=docker/dockerfile:1
FROM alpine:3.21

LABEL org.opencontainers.image.title="seleimend-db-backup" \
      org.opencontainers.image.description="PostgreSQL streaming backup to Backblaze B2 via S3-compatible API" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.authors="Seleimend" \
      org.opencontainers.image.source="https://github.com/victorseleimend293/seleimend-db-backup"

ARG TARGETARCH
ARG SUPERCRONIC_VERSION=v0.2.33

# Install runtime dependencies:
# - postgresql17-client: pg_dump, pg_restore, pg_isready
# - aws-cli: S3-compatible streaming multipart uploads to Backblaze B2
# - zstd, gzip, coreutils, curl, ca-certificates, bash, shadow
RUN apk add --no-cache \
        bash \
        curl \
        ca-certificates \
        coreutils \
        postgresql17-client \
        aws-cli \
        zstd \
        gzip \
        shadow \
    && case "${TARGETARCH:-amd64}" in \
        amd64) ARCH="amd64" ;; \
        arm64) ARCH="arm64" ;; \
        arm) ARCH="arm" ;; \
        *) ARCH="amd64" ;; \
    esac \
    && curl -fsSL "https://github.com/aptible/supercronic/releases/download/${SUPERCRONIC_VERSION}/supercronic-linux-${ARCH}" -o /usr/local/bin/supercronic \
    && chmod +x /usr/local/bin/supercronic

# Create a dedicated non-root user and group
ENV USER=backup \
    UID=10001 \
    GID=10001

RUN addgroup -g ${GID} ${USER} \
    && adduser -u ${UID} -G ${USER} -s /bin/bash -D ${USER} \
    && mkdir -p /scripts /tmp /backups \
    && chown -R ${USER}:${USER} /scripts /tmp /backups

WORKDIR /scripts

# Copy scripts and set permissions
COPY --chown=${USER}:${USER} scripts/ /scripts/

RUN chmod +x /scripts/*.sh

USER ${USER}

ENTRYPOINT ["/scripts/entrypoint.sh"]
CMD ["backup"]
