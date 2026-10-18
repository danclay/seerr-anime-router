FROM alpine:3.24

ENV SUPERCRONIC_URL=https://github.com/aptible/supercronic/releases/download/v0.2.50
ENV SUPERCRONIC_SHA1SUM_AMD64=0795da10bf6303e9680a2c2bd8dd6b9aa33ebda2
ENV SUPERCRONIC_SHA1SUM_ARM64=1d03803120f035569dc528cee117b9220ee959b8

RUN apk add --no-cache bash curl jq tzdata ca-certificates && \
    ARCH=$(uname -m) && \
    if [ "$ARCH" = "x86_64" ]; then \
      SUPERCRONIC_BIN="supercronic-linux-amd64" && \
      SUPERCRONIC_SHA1=$SUPERCRONIC_SHA1SUM_AMD64; \
    elif [ "$ARCH" = "aarch64" ]; then \
      SUPERCRONIC_BIN="supercronic-linux-arm64" && \
      SUPERCRONIC_SHA1=$SUPERCRONIC_SHA1SUM_ARM64; \
    fi && \
    curl -fsSL "${SUPERCRONIC_URL}/${SUPERCRONIC_BIN}" -o /usr/local/bin/supercronic && \
    chmod +x /usr/local/bin/supercronic

WORKDIR /app

COPY script.sh /app/script.sh
COPY entrypoint.sh /app/entrypoint.sh

# Set ownership to standard Alpine 'nobody' user and group
RUN chmod +x /app/script.sh /app/entrypoint.sh && \
    chown -R nobody:nobody /app

USER nobody

ENTRYPOINT ["/app/entrypoint.sh"]
