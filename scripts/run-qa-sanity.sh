#!/usr/bin/env bash
set -euo pipefail

qa_command="${QA_TEST_COMMAND:-}"
base_requirements="${QA_BASE_REQUIREMENTS:-agent/requirements-qa-base.txt}"
pip_quiet_flag="${QA_PIP_QUIET_FLAG:---quiet}"

section() {
  echo
  echo "============================================================"
  echo "$1"
  echo "============================================================"
}

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

section "QA Sanity Run"
printf "%-12s %s\n" "Customer:" "${CUSTOMER}"
printf "%-12s %s\n" "Target URL:" "${TARGET_URL}"
printf "%-12s %s\n" "Browser:" "${BROWSER}"
printf "%-12s %s\n" "Tags:" "${TEST_TAGS}"
printf "%-12s %s\n" "Node:" "${NODE_NAME:-unknown}"
if [[ -n "${QA_PASSWORD_FERNET_KEY:-}" ]]; then
  printf "%-12s %s\n" "Fernet key:" "configured"
else
  printf "%-12s %s\n" "Fernet key:" "not configured"
fi
if [[ -n "${APP_PASSWORD:-}" ]]; then
  printf "%-12s %s\n" "App pass:" "configured"
else
  printf "%-12s %s\n" "App pass:" "not configured"
fi
printf "%-12s %s\n" "Started:" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"

section "Environment Setup"
python3 -m venv --system-site-packages .venv
. .venv/bin/activate
python -m pip install ${pip_quiet_flag} --upgrade pip
if [[ -f "${base_requirements}" ]]; then
  echo "Installing base requirements: ${base_requirements}"
  python -m pip install ${pip_quiet_flag} -r "${base_requirements}"
else
  echo "Base QA requirements file not found: ${base_requirements}" >&2
fi
if [[ -f requirements.txt ]]; then
  echo "Installing project requirements: requirements.txt"
  python -m pip install ${pip_quiet_flag} -r requirements.txt
fi
if ! command -v behave >/dev/null 2>&1; then
  echo "behave is still not available after dependency installation." >&2
  exit 21
fi
printf "%-12s %s\n" "Python:" "$(python --version 2>&1)"
printf "%-12s %s\n" "Pip:" "$(python -m pip --version)"
printf "%-12s %s\n" "Behave:" "$(behave --version)"
printf "%-12s %s\n" "Behave bin:" "$(command -v behave)"

section "QA Command"
echo "${qa_command}"

set +e
section "QA Results"
bash -lc "${qa_command}"
exit_code="$?"
set -e

section "QA Summary"
printf "%-12s %s\n" "Exit code:" "${exit_code}"
printf "%-12s %s\n" "Completed:" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
if [[ "${exit_code}" -eq 0 ]]; then
  echo "Status: PASS"
else
  echo "Status: FAIL"
fi

exit "${exit_code}"
