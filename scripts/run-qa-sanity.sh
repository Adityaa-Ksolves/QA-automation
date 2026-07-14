#!/usr/bin/env bash
set -euo pipefail

artifact_root="${WORKSPACE_ARTIFACT_DIR:-artifacts}"
log_dir="${artifact_root}/logs"
result_dir="${artifact_root}/test-results"
screenshot_dir="${artifact_root}/screenshots"
qa_command="${QA_TEST_COMMAND:-}"

mkdir -p "${log_dir}" "${result_dir}" "${screenshot_dir}"

run_summary="${artifact_root}/qa-run-summary.txt"

{
  echo "customer=${CUSTOMER:-unknown}"
  echo "target_url=${TARGET_URL:-${ENVIRONMENT_URL:-unknown}}"
  echo "browser=${BROWSER:-chrome}"
  echo "test_tags=${TEST_TAGS:-}"
  echo "node=${NODE_NAME:-unknown}"
  echo "started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "${run_summary}"

if [[ -z "${qa_command}" ]]; then
  {
    echo "QA_TEST_COMMAND is required."
    echo "Set it in the Jenkins parameter or job configuration to the existing QA sanity command."
    echo "Example:"
    echo "behave features --tags \"\${TEST_TAGS}\" -D browser=\"\${BROWSER}\" -D endpoint=\"\${TARGET_URL}\" --junit --junit-directory artifacts/test-results"
  } | tee "${log_dir}/qa-command-missing.log"
  exit 20
fi

export TARGET_URL="${TARGET_URL:-${ENVIRONMENT_URL:-}}"
export ENVIRONMENT_URL="${ENVIRONMENT_URL:-${TARGET_URL}}"
export BROWSER="${BROWSER:-chrome}"
export TEST_TAGS="${TEST_TAGS:-}"
export CUSTOMER="${CUSTOMER:-unknown}"
export QA_SECRET_DIR="${QA_SECRET_DIR:-/home/jenkins/qa-secrets}"
export WORKSPACE_ARTIFACT_DIR="${artifact_root}"

echo "Running QA command for ${CUSTOMER} against ${TARGET_URL}" | tee "${log_dir}/qa-command.log"
echo "${qa_command}" >> "${log_dir}/qa-command.log"

set +e
bash -lc "${qa_command}" > >(tee "${log_dir}/qa-stdout.log") 2> >(tee "${log_dir}/qa-stderr.log" >&2)
exit_code="$?"
set -e

echo "exit_code=${exit_code}" | tee -a "${run_summary}"
echo "completed_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "${run_summary}"

exit "${exit_code}"
