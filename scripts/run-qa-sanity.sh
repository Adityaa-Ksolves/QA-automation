#!/usr/bin/env bash
set -euo pipefail

qa_command="${QA_TEST_COMMAND:-}"
base_requirements="${QA_BASE_REQUIREMENTS:-agent/requirements-qa-base.txt}"

if [[ -z "${qa_command}" ]]; then
  echo "QA_TEST_COMMAND is required." >&2
  echo "Set it in the Jenkins parameter or job configuration to the existing QA sanity command." >&2
  echo "Example:" >&2
  echo "behave features --tags \"\${TEST_TAGS}\" -D browser=\"\${BROWSER}\" -D endpoint=\"\${TARGET_URL}\"" >&2
  exit 20
fi

export TARGET_URL="${TARGET_URL:-${ENVIRONMENT_URL:-}}"
export ENVIRONMENT_URL="${ENVIRONMENT_URL:-${TARGET_URL}}"
export BROWSER="${BROWSER:-chrome}"
export TEST_TAGS="${TEST_TAGS:-}"
export CUSTOMER="${CUSTOMER:-unknown}"
export QA_SECRET_DIR="${QA_SECRET_DIR:-/home/jenkins/qa-secrets}"

echo "QA sanity run"
echo "customer=${CUSTOMER}"
echo "target_url=${TARGET_URL}"
echo "browser=${BROWSER}"
echo "test_tags=${TEST_TAGS}"
echo "node=${NODE_NAME:-unknown}"
echo "started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo
echo "Preparing Python QA environment"
python3 -m venv --system-site-packages .venv
. .venv/bin/activate
python -m pip install --upgrade pip
if [[ -f "${base_requirements}" ]]; then
  python -m pip install -r "${base_requirements}"
else
  echo "Base QA requirements file not found: ${base_requirements}" >&2
fi
if [[ -f requirements.txt ]]; then
  python -m pip install -r requirements.txt
fi
if ! command -v behave >/dev/null 2>&1; then
  echo "behave is still not available after dependency installation." >&2
  exit 21
fi
echo "behave=$(command -v behave)"
echo
echo "Running QA command:"
echo "${qa_command}"
echo

set +e
bash -lc "${qa_command}"
exit_code="$?"
set -e

echo
echo "QA command completed"
echo "exit_code=${exit_code}"
echo "completed_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"

exit "${exit_code}"
