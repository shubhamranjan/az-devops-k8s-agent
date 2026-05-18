#!/bin/bash
set -euo pipefail

if [ -z "${AZP_URL:-}" ]; then
  echo 1>&2 "error: missing AZP_URL environment variable"
  exit 1
fi

if [ -z "${AZP_TOKEN_FILE:-}" ]; then
  if [ -z "${AZP_TOKEN:-}" ]; then
    echo 1>&2 "error: missing AZP_TOKEN environment variable"
    exit 1
  fi
  AZP_TOKEN_FILE=/azp/.token
  echo -n "$AZP_TOKEN" > "$AZP_TOKEN_FILE"
  chmod 600 "$AZP_TOKEN_FILE"
fi
unset AZP_TOKEN

if [ -n "${AZP_WORK:-}" ]; then
  mkdir -p "$AZP_WORK"
fi

export AGENT_ALLOW_RUNASROOT="1"
export VSO_AGENT_IGNORE=AZP_TOKEN,AZP_TOKEN_FILE

print_header() {
  local lightcyan='\033[1;36m'
  local nocolor='\033[0m'
  echo -e "${lightcyan}$1${nocolor}"
}

cleanup() {
  if [ -e config.sh ]; then
    print_header "Cleanup. Removing Azure Pipelines agent..."
    local attempts=0
    until ./config.sh remove --unattended --auth PAT --token "$(cat "$AZP_TOKEN_FILE")"; do
      attempts=$((attempts + 1))
      if [ "$attempts" -ge 10 ]; then
        echo 1>&2 "error: agent removal failed after $attempts attempts; giving up"
        return 1
      fi
      echo "Retrying in 30 seconds... (attempt $attempts/10)"
      sleep 30
    done
  fi
}

# Map TARGETARCH (BuildKit names: amd64, arm64, arm) to Azure platform naming.
case "${TARGETARCH:-amd64}" in
  amd64)      AZP_PLATFORM=linux-x64 ;;
  arm64)      AZP_PLATFORM=linux-arm64 ;;
  arm)        AZP_PLATFORM=linux-arm ;;
  linux-*)    AZP_PLATFORM="$TARGETARCH" ;;
  *)          AZP_PLATFORM="linux-${TARGETARCH}" ;;
esac

print_header "1. Determining matching Azure Pipelines agent (platform=$AZP_PLATFORM)..."

AZP_AGENT_PACKAGES=$(curl --fail --location --silent --show-error \
    -u "user:$(cat "$AZP_TOKEN_FILE")" \
    -H 'Accept:application/json;' \
    "$AZP_URL/_apis/distributedtask/packages/agent?platform=${AZP_PLATFORM}&top=1")

AZP_AGENT_PACKAGE_LATEST_URL=$(echo "$AZP_AGENT_PACKAGES" | jq -r '.value[0].downloadUrl')
AZP_AGENT_PACKAGE_EXPECTED_HASH=$(echo "$AZP_AGENT_PACKAGES" | jq -r '.value[0].hashValue')

if [ -z "$AZP_AGENT_PACKAGE_LATEST_URL" ] || [ "$AZP_AGENT_PACKAGE_LATEST_URL" = "null" ]; then
  echo 1>&2 "error: could not determine a matching Azure Pipelines agent"
  echo 1>&2 "check AZP_URL='$AZP_URL', token validity, and AZP_PLATFORM='$AZP_PLATFORM'"
  exit 1
fi

print_header "2. Downloading and extracting Azure Pipelines agent..."

AGENT_TGZ=/tmp/agent.tgz
if ! curl --fail --location --silent --show-error --compressed \
        --max-time 600 --output "$AGENT_TGZ" "$AZP_AGENT_PACKAGE_LATEST_URL"; then
  echo 1>&2 "error: failed to download agent from $AZP_AGENT_PACKAGE_LATEST_URL"
  exit 1
fi

if ! file "$AGENT_TGZ" | grep -q 'gzip compressed'; then
  echo 1>&2 "error: downloaded file is not a gzip archive (egress proxy? CDN error page?)"
  echo 1>&2 "first 400 bytes of body:"
  head -c 400 "$AGENT_TGZ" 1>&2
  exit 1
fi

if [ -n "$AZP_AGENT_PACKAGE_EXPECTED_HASH" ] && [ "$AZP_AGENT_PACKAGE_EXPECTED_HASH" != "null" ]; then
  ACTUAL_HASH=$(sha256sum "$AGENT_TGZ" | awk '{print $1}')
  if [ "$AZP_AGENT_PACKAGE_EXPECTED_HASH" != "$ACTUAL_HASH" ]; then
    echo 1>&2 "error: hash mismatch (expected $AZP_AGENT_PACKAGE_EXPECTED_HASH, got $ACTUAL_HASH)"
    exit 1
  fi
fi

tar -xzf "$AGENT_TGZ"
rm -f "$AGENT_TGZ"

# env.sh is shipped by the Azure DevOps agent and is not strict-mode-clean
# (uses ${!var} indirect expansion against potentially-unset names).
# Relax -e and -u for the duration of the source, then re-enable.
set +eu
source ./env.sh
set -eu

print_header "3. Configuring Azure Pipelines agent..."

./config.sh --unattended \
  --agent "${AZP_AGENT_NAME:-$(hostname)}" \
  --url "$AZP_URL" \
  --auth PAT \
  --token "$(cat "$AZP_TOKEN_FILE")" \
  --pool "${AZP_POOL:-Default}" \
  --work "${AZP_WORK:-_work}" \
  --replace \
  --acceptTeeEula & wait $!

print_header "4. Running Azure Pipelines agent..."

trap 'cleanup; exit 0' EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

chmod +x ./run-docker.sh
./run-docker.sh "$@" & wait $!
BASH_EOF

# Verify
head -1 start.sh | xxd | head -1   # should show "23 21 2f 62 69 6e 2f 62 61 73 68" (#!/bin/bash)
file start.sh                       # should say "ASCII text" or "Unicode text" — NOT "with CRLF"