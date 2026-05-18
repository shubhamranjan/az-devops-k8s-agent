start.sh

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

  cleanup() {
    if [ -e config.sh ]; then
      print_header "Cleanup. Removing Azure Pipelines agent..."

      # If the agent has running jobs, removal will fail — retry until it succeeds.
      while true; do
        ./config.sh remove --unattended --auth PAT --token "$(cat "$AZP_TOKEN_FILE")" && break
        echo "Retrying in 30 seconds..."
        sleep 30
      done
    fi
  }

  print_header() {
    local lightcyan='\033[1;36m'
    local nocolor='\033[0m'
    echo -e "${lightcyan}$1${nocolor}"
  }

  # Let the agent ignore the token env variables
  export VSO_AGENT_IGNORE=AZP_TOKEN,AZP_TOKEN_FILE

  print_header "1. Determining matching Azure Pipelines agent..."

  AZP_AGENT_PACKAGES=$(curl --fail --location --silent --show-error \
      -u "user:$(cat "$AZP_TOKEN_FILE")" \
      -H 'Accept:application/json;' \
      "$AZP_URL/_apis/distributedtask/packages/agent?platform=${TARGETARCH}&top=1")

  AZP_AGENT_PACKAGE_LATEST_URL=$(echo "$AZP_AGENT_PACKAGES" | jq -r '.value[0].downloadUrl')
  AZP_AGENT_PACKAGE_EXPECTED_HASH=$(echo "$AZP_AGENT_PACKAGES" | jq -r '.value[0].hashValue')

  if [ -z "$AZP_AGENT_PACKAGE_LATEST_URL" ] || [ "$AZP_AGENT_PACKAGE_LATEST_URL" = "null" ]; then
    echo 1>&2 "error: could not determine a matching Azure Pipelines agent"
    echo 1>&2 "check that account '$AZP_URL' is correct, the token is valid, and TARGETARCH='$TARGETARCH' is a known platform"
    exit 1
  fi

  print_header "2. Downloading and extracting Azure Pipelines agent..."

  AGENT_TGZ=/tmp/agent.tgz

  if ! curl --fail --location --silent --show-error --compressed \
          --max-time 600 \
          --output "$AGENT_TGZ" "$AZP_AGENT_PACKAGE_LATEST_URL"; then
    echo 1>&2 "error: failed to download agent from $AZP_AGENT_PACKAGE_LATEST_URL"
    exit 1
  fi

  if ! file "$AGENT_TGZ" | grep -q 'gzip compressed'; then
    echo 1>&2 "error: downloaded file is not a gzip archive (egress proxy intercepting? CDN error page?)"
    echo 1>&2 "first 400 bytes of body:"
    head -c 400 "$AGENT_TGZ" 1>&2
    exit 1
  fi

  if [ -n "$AZP_AGENT_PACKAGE_EXPECTED_HASH" ] && [ "$AZP_AGENT_PACKAGE_EXPECTED_HASH" != "null" ]; then
    ACTUAL_HASH=$(sha256sum "$AGENT_TGZ" | awk '{print $1}')
    if [ "$AZP_AGENT_PACKAGE_EXPECTED_HASH" != "$ACTUAL_HASH" ]; then
      echo 1>&2 "error: hash mismatch"
      echo 1>&2 "  expected: $AZP_AGENT_PACKAGE_EXPECTED_HASH"
      echo 1>&2 "  actual:   $ACTUAL_HASH"
      exit 1
    fi
  fi

  tar -xzf "$AGENT_TGZ"
  rm -f "$AGENT_TGZ"

  source ./env.sh

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

  # Run the agent with TERM/INT signal awareness. Add --once if you want
  # single-shot behavior (agent exits after one build).
  ./run-docker.sh "$@" & wait $!