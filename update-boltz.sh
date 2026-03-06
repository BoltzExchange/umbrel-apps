#!/usr/bin/env bash
set -euo pipefail

# Update boltz-client in both RTL apps (LND + CLN)

REPO="boltz/boltz-client"
APPS=("ride-the-lightning" "core-lightning-rtl")

CURRENT_TAG=$(grep -oP "image: ${REPO}:\K[^@]+" "${APPS[0]}/docker-compose.yml" | head -1)
echo "current: ${CURRENT_TAG}"

LATEST_TAG=$(
  curl -s "https://hub.docker.com/v2/repositories/${REPO}/tags?page_size=50&ordering=last_updated" \
    | jq -r '[.results[] | select(.name | test("^[0-9]+\\.[0-9]+\\.[0-9]+$"))] | sort_by(.name | split(".") | map(tonumber)) | last | .name'
)

if [[ -z "${LATEST_TAG}" ]]; then
  echo "error: could not resolve latest tag" >&2
  exit 1
fi

echo "latest:  ${LATEST_TAG}"

if [[ "${CURRENT_TAG}" == "${LATEST_TAG}" ]]; then
  echo "already up to date"
  exit 0
fi

DIGEST=$(
  curl -s "https://hub.docker.com/v2/repositories/${REPO}/tags/${LATEST_TAG}" \
    | jq -r '.digest'
)

if [[ -z "${DIGEST}" || "${DIGEST}" == "null" ]]; then
  echo "error: could not fetch digest for ${LATEST_TAG}" >&2
  exit 1
fi

NEW_IMAGE="${REPO}:${LATEST_TAG}@${DIGEST}"

# Update docker-compose.yml and umbrel-app.yml in each app
for app in "${APPS[@]}"; do
  sed -i "s|image: ${REPO}:[^[:space:]]*|image: ${NEW_IMAGE}|" "${app}/docker-compose.yml"

  appfile="${app}/umbrel-app.yml"
  BASE_VERSION=$(grep -oP '^version:\s*"\K[^"]+' "${appfile}" | sed 's/-boltz.*//')
  sed -i "s|^version:.*|version: \"${BASE_VERSION}-boltz\"|" "${appfile}"

  awk -v tag="${LATEST_TAG}" '
    /^releaseNotes:/ {
      print "releaseNotes: >-"
      print "  This release contains the following updates:"
      print "    - Bump boltz-client to " tag
      skip = 1
      next
    }
    skip && /^[^ ]/ { skip = 0 }
    !skip { print }
  ' "${appfile}" > "${appfile}.tmp" && mv "${appfile}.tmp" "${appfile}"
done

echo "updated: ${CURRENT_TAG} → ${LATEST_TAG}"
