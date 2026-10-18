#!/usr/bin/env bash

set -euo pipefail

CRON_SCHEDULE="${CRON_SCHEDULE:-*/15 * * * *}"

# Export environment variables for cron executions into /tmp/env.sh
export -p | grep -E -v ' (BASH_VERSINFO|BASH|ENV|HOME|IFS|PPID|PWD|SHELL|_)=' > /tmp/env.sh
chmod 600 /tmp/env.sh

# Write crontab file targeting Supercronic
CRONTAB_FILE="/tmp/crontab"
echo "$CRON_SCHEDULE /bin/bash -c 'source /tmp/env.sh && /app/script.sh'" > "$CRONTAB_FILE"

echo "=========================================="
echo "Seerr Anime Router Container Started"
echo "Cron schedule set to: $CRON_SCHEDULE"
echo "=========================================="

echo "Running initial audit on startup..."
/app/script.sh || true
echo "Initial audit complete."

echo "Starting Supercronic runner..."
exec /usr/local/bin/supercronic -passthrough-logs -quiet "$CRONTAB_FILE"

