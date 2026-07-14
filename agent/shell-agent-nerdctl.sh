#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
env_file="${ENV_FILE:-${script_dir}/.env}"

if ! command -v nerdctl >/dev/null 2>&1; then
  echo "nerdctl is required but was not found in PATH." >&2
  exit 1
fi

if [[ ! -f "${env_file}" ]]; then
  echo "Missing env file: ${env_file}" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
. "${env_file}"
set +a

if [[ -z "${JENKINS_AGENT_NAME:-}" ]]; then
  echo "JENKINS_AGENT_NAME is required in ${env_file}." >&2
  exit 1
fi

nerdctl exec -it "${JENKINS_AGENT_NAME}" bash
