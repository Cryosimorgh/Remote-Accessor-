#!/usr/bin/env bash
# Minimal Linux/macOS setup and launcher for Remote Accessor Phase 1.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "\${BASH_SOURCE[0]}")" && pwd)"
VENV="$ROOT/.venv"
ENV_FILE="$ROOT/.env"

fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }

prompt_value() {
    local name="$1" label="$2" fallback="$3" secret="$4"
    local value="\${!name:-}"
    if [[ -z "$value" ]]; then
        [[ -t 0 ]] || fail "$name is unset; provide it as an environment variable or run interactively."
        if [[ "$secret" == yes ]]; then
            read -r -s -p "$label: " value || fail "Could not read $name"
            printf '\n'
        else
            read -r -p "$label\${fallback:+ [$fallback]}: " value || fail "Could not read $name"
        fi
    fi
    [[ -n "$value" ]] || value="$fallback"
    [[ -n "$value" ]] || fail "$name must not be empty"
    printf -v "$name" '%s' "$value"
}

configure() {
    if [[ -e "$ENV_FILE" ]]; then
        printf 'Keeping existing %s (delete it to reconfigure).\n' "$ENV_FILE"
        return
    fi

    printf 'Broker details are saved as plain text in .env (ignored by Git, permissions 600).\n'
    prompt_value RA_MQTT_HOST 'TLS broker hostname (no scheme)' '' no
    prompt_value RA_MQTT_PORT 'TLS port' '8883' no
    prompt_value RA_MQTT_USERNAME 'Agent MQTT username' '' no
    prompt_value RA_MQTT_PASSWORD 'Agent MQTT password (hidden)' '' yes
    prompt_value RA_DEVICE_ID 'Unique PC device ID (letters/numbers/_/-)' '' no

    [[ "$RA_MQTT_PORT" =~ ^[0-9]{1,5}$ ]] && (( 10#$RA_MQTT_PORT >= 1 && 10#$RA_MQTT_PORT <= 65535 )) || fail 'RA_MQTT_PORT must be 1-65535'
    [[ "$RA_DEVICE_ID" =~ ^[a-zA-Z0-9_-]+$ ]] && (( \${#RA_DEVICE_ID} <= 64 )) || fail 'RA_DEVICE_ID must be 1-64 letters/numbers/-/_'

    (umask 077
        {
            printf 'export RA_MQTT_HOST=%q\n' "$RA_MQTT_HOST"
            printf 'export RA_MQTT_PORT=%q\n' "$RA_MQTT_PORT"
            printf 'export RA_MQTT_USERNAME=%q\n' "$RA_MQTT_USERNAME"
            printf 'export RA_MQTT_PASSWORD=%q\n' "$RA_MQTT_PASSWORD"
            printf 'export RA_DEVICE_ID=%q\n' "$RA_DEVICE_ID"
        } > "$ENV_FILE"
    )
    printf 'Saved %s\n' "$ENV_FILE"
}

case "\${1:-setup}" in
    setup)
        command -v python3 >/dev/null 2>&1 || fail 'Install Python 3.9+ first.'
        python3 -c 'import sys; sys.exit(sys.version_info < (3, 9))' || fail 'Python 3.9+ required.'
        if [[ ! -x "$VENV/bin/python" ]]; then
            python3 -m venv "$VENV" || fail 'Could not create venv; install Python venv support.'
        fi
        "$VENV/bin/python" -m pip install -r "$ROOT/requirements.txt"
        configure
        printf '\nReady. Start the agent with: bash setup.sh run\n'
        ;;
    run)
        [[ -x "$VENV/bin/python" ]] || fail 'Run bash setup.sh first to install dependencies.'
        if [[ -f "$ENV_FILE" ]]; then
            # This file is created by the setup script with shell-safe quoting.
            # Only source .env files you trust.
            # shellcheck disable=SC1090
            source "$ENV_FILE"
        fi
        exec "$VENV/bin/python" "$ROOT/agent.py"
        ;;
    test)
        [[ -x "$VENV/bin/python" ]] || fail 'Run bash setup.sh first to install dependencies.'
        exec "$VENV/bin/python" -m unittest -v "$ROOT/test_agent.py"
        ;;
    *)
        fail 'Usage: bash setup.sh [setup|run|test]'
        ;;
esac
