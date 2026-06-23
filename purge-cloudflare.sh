#!/bin/bash
CREDS="${HOME}/Desktop/github/.creds"
[ -f "${CREDS}" ] || { echo "ERROR: ~/.creds not found"; exit 1; }
# shellcheck disable=SC1090
source "${CREDS}"
CF_CF_CREDS="${HOME}/Desktop/github/.cf-credentials"
# shellcheck disable=SC1090
[[ -f "${CF_CF_CREDS}" ]] && source "${CF_CF_CREDS}"

echo "Purging Cloudflare cache for andrewbaker.ninja..."
curl -s -X POST "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/purge_cache" \
  -H "X-Auth-Email: $CF_EMAIL" \
  -H "X-Auth-Key: $CF_KEY" \
  -H "Content-Type: application/json" \
  --data '{"purge_everything":true}' | grep -o '"success":[^,]*'
echo "Done"
