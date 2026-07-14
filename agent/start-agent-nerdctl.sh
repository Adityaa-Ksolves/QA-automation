#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "${script_dir}/.." && pwd)"
env_file="${ENV_FILE:-${script_dir}/.env}"
image_name="${IMAGE_NAME:-qa-jenkins-inbound-agent:latest}"
workdir_host="${AGENT_WORKDIR_HOST:-${project_dir}/.agent-workdir}"

if ! command -v nerdctl >/dev/null 2>&1; then
  echo "nerdctl is required but was not found in PATH." >&2
  exit 1
fi

if [[ ! -f "${env_file}" ]]; then
  echo "Missing env file: ${env_file}" >&2
  echo "Create it from agent/.env.example and fill in Jenkins values." >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
. "${env_file}"
set +a

required_vars=(
  JENKINS_URL
  JENKINS_AGENT_NAME
  JENKINS_SECRET
  CUSTOMER_KEY
)

for var_name in "${required_vars[@]}"; do
  if [[ -z "${!var_name:-}" ]]; then
    echo "Required variable ${var_name} is empty or missing in ${env_file}." >&2
    exit 1
  fi
done

mkdir -p "${workdir_host}"

echo "Building ${image_name} from ${project_dir}/agent/Dockerfile"
nerdctl build \
  -t "${image_name}" \
  -f "${project_dir}/agent/Dockerfile" \
  "${project_dir}"

if nerdctl ps -a --format '{{.Names}}' | grep -Fxq "${JENKINS_AGENT_NAME}"; then
  echo "Removing existing container ${JENKINS_AGENT_NAME}"
  nerdctl rm -f "${JENKINS_AGENT_NAME}"
fi

echo "Starting Jenkins inbound agent ${JENKINS_AGENT_NAME}"
nerdctl run -d \
  --name "${JENKINS_AGENT_NAME}" \
  --restart unless-stopped \
  --env-file "${env_file}" \
  --shm-size 2g \
  -v "${workdir_host}:/home/jenkins/agent" \
  -v "${project_dir}/scripts:/home/jenkins/agent/poc-scripts:ro" \
  "${image_name}" \
  -url "${JENKINS_URL}" \
  -secret "${JENKINS_SECRET}" \
  -name "${JENKINS_AGENT_NAME}" \
  -workDir /home/jenkins/agent

echo "Agent container started."
echo "Follow logs with: ${script_dir}/logs-agent-nerdctl.sh"
