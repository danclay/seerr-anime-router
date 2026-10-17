#!/usr/bin/env bash

set -euo pipefail

CRON_SCHEDULE="${CRON_SCHEDULE:-*/15 * * * *}"

# Ensure temporary directories exist in writable /tmp
mkdir -p /tmp/cron/crontabs /tmp/cron/spool
chmod 700 /tmp/cron/crontabs

# Safely export environment variables to /tmp/env.sh
export -p | grep -E -v ' (BASH_VERSINFO|BASH|ENV|HOME|IFS|PPID|PWD|SHELL|_)=' > /tmp/env.sh
chmod 600 /tmp/env.sh

# Write custom crontab inside /tmp
CRON_FILE="/tmp/cron/crontabs/root"
echo "$CRON_SCHEDULE /bin/bash -c 'source /tmp/env.sh && /app/script.sh' > /proc/1/fd/1 2>&1" > "$CRON_FILE"
chmod 600 "$CRON_FILE"

echo "=========================================="
echo "Seerr Anime Router Container Started (Hardened)"
echo "Cron schedule set to: $CRON_SCHEDULE"
echo "=========================================="

echo "Running initial audit on startup..."
/app/script.sh || true
echo "Initial audit complete."

echo "Starting cron daemon..."
# Point crond to the custom /tmp/cron/crontabs spool directory
exec crond -f -l 8 -c /tmp/cron/crontabs