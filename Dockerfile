FROM alpine:3.19

RUN apk add --no-cache bash curl jq tzdata && \
    addgroup -g 1000 appgroup && \
    adduser -u 1000 -G appgroup -D -s /bin/bash appuser

WORKDIR /app

COPY script.sh /app/script.sh
COPY entrypoint.sh /app/entrypoint.sh

RUN chmod +x /app/script.sh /app/entrypoint.sh && \
    chown -R appuser:appgroup /app

USER appuser

ENTRYPOINT ["/app/entrypoint.sh"]