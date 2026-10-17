#!/usr/bin/env bash

# ==============================================================================
# Seerr Request Manager & Anime Router
# Features:
#  1. Routes Anime requests to dedicated Sonarr/Radarr Anime instances.
#  2. Routes non-Anime requests mistakenly sent to Anime instances back to standard instances.
#  3. Auto-rejects 4K requests for Anime content.
#  4. Automatically approves pending requests post-correction (configurable).
#  5. Optional quiet output mode (ONLY_ERRORS=true).
# ==============================================================================

set -euo pipefail

# --- ENVIRONMENT VARIABLES ---
SEERR_URL="${SEERR_URL:-${1:-}}"
API_KEY="${API_KEY:-${2:-}}"

SONARR_STANDARD_SERVER_ID="${SONARR_STANDARD_SERVER_ID:-}"
SONARR_ANIME_SERVER_ID="${SONARR_ANIME_SERVER_ID:-}"
RADARR_STANDARD_SERVER_ID="${RADARR_STANDARD_SERVER_ID:-}"
RADARR_ANIME_SERVER_ID="${RADARR_ANIME_SERVER_ID:-}"

ENABLE_AUTO_APPROVE="${ENABLE_AUTO_APPROVE:-false}"
ONLY_ERRORS="${ONLY_ERRORS:-false}"

# Optional overrides. Else uses defaults for the respective server
SONARR_ANIME_PROFILE_ID="${SONARR_ANIME_PROFILE_ID:-}"
SONARR_ANIME_ROOT_FOLDER="${SONARR_ANIME_ROOT_FOLDER:-}"
RADARR_ANIME_PROFILE_ID="${RADARR_ANIME_PROFILE_ID:-}"
RADARR_ANIME_ROOT_FOLDER="${RADARR_ANIME_ROOT_FOLDER:-}"

SONARR_STANDARD_PROFILE_ID="${SONARR_STANDARD_PROFILE_ID:-}"
SONARR_STANDARD_ROOT_FOLDER="${SONARR_STANDARD_ROOT_FOLDER:-}"
RADARR_STANDARD_PROFILE_ID="${RADARR_STANDARD_PROFILE_ID:-}"
RADARR_STANDARD_ROOT_FOLDER="${RADARR_STANDARD_ROOT_FOLDER:-}"

# Helper function for conditional info logging
log_info() {
  if [ "$ONLY_ERRORS" != "true" ]; then
    echo "$@"
  fi
}

# ==============================================================================

if [ -z "$SEERR_URL" ]; then
  echo "[ERROR] SEERR_URL parameter or environment variable is missing." >&2
  exit 1
fi

if [ -z "$API_KEY" ]; then
  echo "[ERROR] API_KEY parameter or environment variable is missing." >&2
  exit 1
fi

# Verify required dependencies
for tool in curl jq; do
  if ! command -v "$tool" &> /dev/null; then
    echo "[ERROR] Required command '$tool' is not installed." >&2
    exit 1
  fi
done

log_info "--------------------------------------------------"
log_info "Running request audit at $(date)..."
log_info "Fetching open requests from Seerr (${SEERR_URL})..."

# Fetch requests from Seerr API with detailed error logging
TMP_RESPONSE=$(mktemp)
TMP_ERRORS=$(mktemp)

CURL_EXIT_CODE=0
HTTP_STATUS=$(curl -s -S \
  -o "$TMP_RESPONSE" \
  -w "%{http_code}" \
  --connect-timeout 10 \
  --max-time 30 \
  -H "X-Api-Key: ${API_KEY}" \
  "${SEERR_URL}/api/v1/request?take=100&skip=0&filter=all" 2> "$TMP_ERRORS") || CURL_EXIT_CODE=$?

RESPONSE_BODY=$(cat "$TMP_RESPONSE")
ERROR_MSG=$(cat "$TMP_ERRORS")
rm -f "$TMP_RESPONSE" "$TMP_ERRORS"

if [ "$CURL_EXIT_CODE" -ne 0 ]; then
  echo "[ERROR] Curl network failure (Exit Code: ${CURL_EXIT_CODE})." >&2
  echo "  Details: ${ERROR_MSG}" >&2
  exit 1
fi

if [ "$HTTP_STATUS" -ne 200 ]; then
  echo "[ERROR] Seerr returned HTTP status ${HTTP_STATUS}." >&2
  echo "  Response body: ${RESPONSE_BODY}" >&2
  exit 1
fi

REQUESTS_JSON="$RESPONSE_BODY"
COUNT=$(echo "$REQUESTS_JSON" | jq -r '.results | length // 0')
log_info "Found ${COUNT} total requests in Seerr."

if [ "$COUNT" -eq 0 ]; then
  log_info "No requests found to process."
  exit 0
fi

# Process requests
while read -r req; do
  [ -z "$req" ] && continue

  REQ_ID=$(echo "$req" | jq -r '.id')
  STATUS=$(echo "$req" | jq -r '.status') # 1 = Pending, 2 = Approved, 3 = Declined
  MEDIA_TYPE=$(echo "$req" | jq -r '.type // .media.mediaType')
  CURRENT_SERVER_ID=$(echo "$req" | jq -r '.serverId // empty')
  IS_4K=$(echo "$req" | jq -r '.is4k // false')
  TMDB_ID=$(echo "$req" | jq -r '.media.tmdbId')
  ORIGINAL_LANG=$(echo "$req" | jq -r '.media.originalLanguage // empty')

  # Extract season numbers as flat integers (e.g. [1, 2])
  SEASONS=$(echo "$req" | jq -c '[.seasons[]? | if type == "object" then .seasonNumber else . end]')

  # Determine if content is Anime
  IS_ANIME=false

  if [ "$ORIGINAL_LANG" = "ja" ]; then
    IS_ANIME=true
  else
    if [ "$MEDIA_TYPE" = "tv" ]; then
      SHOW_INFO=$(curl -s -H "X-Api-Key: ${API_KEY}" "${SEERR_URL}/api/v1/tv/${TMDB_ID}")
      GENRES=$(echo "$SHOW_INFO" | jq -r '.genres[].id // empty')
      ORIGIN_COUNTRY=$(echo "$SHOW_INFO" | jq -r '.originCountry[]? // empty')

      if echo "$ORIGIN_COUNTRY" | grep -q "JP" && echo "$GENRES" | grep -q "16"; then
        IS_ANIME=true
      fi

    elif [ "$MEDIA_TYPE" = "movie" ]; then
      MOVIE_INFO=$(curl -s -H "X-Api-Key: ${API_KEY}" "${SEERR_URL}/api/v1/movie/${TMDB_ID}")
      GENRES=$(echo "$MOVIE_INFO" | jq -r '.genres[].id // empty')
      ORIG_LANG=$(echo "$MOVIE_INFO" | jq -r '.originalLanguage // empty')

      if [ "$ORIG_LANG" = "ja" ] && echo "$GENRES" | grep -q "16"; then
        IS_ANIME=true
      fi
    fi
  fi

  # Skip requests that are not Pending (Status 1)
  if [ "$STATUS" -ne 1 ]; then
    log_info "Request #${REQ_ID} (${MEDIA_TYPE}): Skipping (Status is not Pending)."
    continue
  fi

  WAS_CORRECTED=false

  # --- RULE 1: AUTO-REJECT 4K ANIME REQUESTS ---
  if [ "$IS_ANIME" = true ] && [ "$IS_4K" = true ]; then
    echo "Request #${REQ_ID} (${MEDIA_TYPE}): Flagged as 4K Anime. Rejecting request..."
    REJECT_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
      -H "X-Api-Key: ${API_KEY}" \
      "${SEERR_URL}/api/v1/request/${REQ_ID}/decline")

    if [ "$REJECT_STATUS" -eq 200 ] || [ "$REJECT_STATUS" -eq 202 ]; then
      echo "  [OK] Request #${REQ_ID} successfully rejected."
    else
      echo "  [ERROR] Failed to reject Request #${REQ_ID} (HTTP Status: ${REJECT_STATUS})." >&2
    fi
    continue
  fi

  # --- RULE 2: TARGET SERVER SELECTION & AUTO-LOOKUP ---
  TARGET_SERVER_ID=""
  TARGET_PROFILE_ID=""
  TARGET_ROOT_FOLDER=""
  SERVICE_TYPE=""

  if [ "$IS_ANIME" = true ]; then
    if [ "$MEDIA_TYPE" = "tv" ]; then
      TARGET_SERVER_ID="$SONARR_ANIME_SERVER_ID"
      TARGET_PROFILE_ID="$SONARR_ANIME_PROFILE_ID"
      TARGET_ROOT_FOLDER="$SONARR_ANIME_ROOT_FOLDER"
      SERVICE_TYPE="sonarr"
    elif [ "$MEDIA_TYPE" = "movie" ]; then
      TARGET_SERVER_ID="$RADARR_ANIME_SERVER_ID"
      TARGET_PROFILE_ID="$RADARR_ANIME_PROFILE_ID"
      TARGET_ROOT_FOLDER="$RADARR_ANIME_ROOT_FOLDER"
      SERVICE_TYPE="radarr"
    fi
  else
    if [ "$MEDIA_TYPE" = "tv" ]; then
      TARGET_SERVER_ID="$SONARR_STANDARD_SERVER_ID"
      TARGET_PROFILE_ID="$SONARR_STANDARD_PROFILE_ID"
      TARGET_ROOT_FOLDER="$SONARR_STANDARD_ROOT_FOLDER"
      SERVICE_TYPE="sonarr"
    elif [ "$MEDIA_TYPE" = "movie" ]; then
      TARGET_SERVER_ID="$RADARR_STANDARD_SERVER_ID"
      TARGET_PROFILE_ID="$RADARR_STANDARD_PROFILE_ID"
      TARGET_ROOT_FOLDER="$RADARR_STANDARD_ROOT_FOLDER"
      SERVICE_TYPE="radarr"
    fi
  fi

  # Apply server reassignment if current server ID doesn't match target
  if [ -n "$TARGET_SERVER_ID" ] && [ "$CURRENT_SERVER_ID" != "$TARGET_SERVER_ID" ]; then
    echo "Request #${REQ_ID} (${MEDIA_TYPE}, Anime: ${IS_ANIME}): Reassigning server..."
    echo "  Current Server: ${CURRENT_SERVER_ID:-'None'} -> Target Server: ${TARGET_SERVER_ID}"

    # Auto-fetch server defaults if profileId or rootFolder were left blank
    if [ -z "$TARGET_PROFILE_ID" ] || [ -z "$TARGET_ROOT_FOLDER" ]; then
      SERVER_CONFIG=$(curl -s -H "X-Api-Key: ${API_KEY}" "${SEERR_URL}/api/v1/settings/${SERVICE_TYPE}")
      MATCHED_SERVER=$(echo "$SERVER_CONFIG" | jq -c ".[] | select(.id == ($TARGET_SERVER_ID | tonumber))")

      if [ -z "$TARGET_PROFILE_ID" ]; then
        TARGET_PROFILE_ID=$(echo "$MATCHED_SERVER" | jq -r '.activeProfileId // empty')
      fi
      if [ -z "$TARGET_ROOT_FOLDER" ]; then
        TARGET_ROOT_FOLDER=$(echo "$MATCHED_SERVER" | jq -r '.activeDirectory // empty')
      fi
    fi

    # Construct payload with mediaType and flattened seasons array
    PAYLOAD=$(jq -n \
      --arg mediaType "$MEDIA_TYPE" \
      --arg serverId "$TARGET_SERVER_ID" \
      --arg profileId "$TARGET_PROFILE_ID" \
      --arg rootFolder "$TARGET_ROOT_FOLDER" \
      --argjson seasons "$SEASONS" \
      '{
        mediaType: $mediaType,
        serverId: ($serverId | tonumber),
        profileId: ($profileId | tonumber),
        rootFolder: $rootFolder
      } + (if $mediaType == "tv" and ($seasons | length > 0) then {seasons: $seasons} else {} end)')

    RESPONSE=$(curl -s -w "\n%{http_code}" -X PUT \
      -H "X-Api-Key: ${API_KEY}" \
      -H "Content-Type: application/json" \
      -d "$PAYLOAD" \
      "${SEERR_URL}/api/v1/request/${REQ_ID}")

    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    RESPONSE_BODY=$(echo "$RESPONSE" | sed '$d')

    if [ "$HTTP_CODE" -eq 200 ] || [ "$HTTP_CODE" -eq 202 ]; then
      echo "  [OK] Request #${REQ_ID} re-assigned successfully."
      WAS_CORRECTED=true
    else
      echo "  [ERROR] Failed to update Request #${REQ_ID} (HTTP Status: ${HTTP_CODE})." >&2
      echo "  Details: ${RESPONSE_BODY}" >&2
    fi
  fi

  # --- RULE 3: AUTO-APPROVAL ---
  if [ "$ENABLE_AUTO_APPROVE" = "true" ]; then
    echo "Request #${REQ_ID}: Approving request..."

    APPROVE_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
      -H "X-Api-Key: ${API_KEY}" \
      "${SEERR_URL}/api/v1/request/${REQ_ID}/approve")

    if [ "$APPROVE_STATUS" -eq 200 ] || [ "$APPROVE_STATUS" -eq 202 ]; then
      echo "  [OK] Request #${REQ_ID} approved."
    else
      echo "  [ERROR] Failed to approve Request #${REQ_ID} (HTTP Status: ${APPROVE_STATUS})." >&2
    fi
  fi
done < <(echo "$REQUESTS_JSON" | jq -c '.results[]?')

log_info "Finished processing requests."