#!/usr/bin/env bash
set -euo pipefail

qa_command="${QA_TEST_COMMAND:-}"
base_requirements="${QA_BASE_REQUIREMENTS:-agent/requirements-qa-base.txt}"
pip_quiet_flag="${QA_PIP_QUIET_FLAG:---quiet}"
artifacts_dir="${QA_ARTIFACTS_DIR:-artifacts}"
log_dir="${artifacts_dir}/logs"
test_results_dir="${artifacts_dir}/test-results"
raw_log="${log_dir}/qa-raw.log"
stream_raw_log="${QA_STREAM_RAW_LOG:-0}"

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

mkdir -p "${log_dir}" "${test_results_dir}"

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
printf "%-12s %s\n" "Raw log:" "${raw_log}"
printf "%-12s %s\n" "JUnit:" "${test_results_dir}"

section "Environment Setup"
python3 -m venv --system-site-packages .venv
. .venv/bin/activate
export PATH
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
if [[ "${stream_raw_log}" == "1" ]]; then
  bash -o pipefail -c "${qa_command}" 2>&1 | tee "${raw_log}"
  exit_code="${PIPESTATUS[0]}"
else
  echo "Running QA command. Full Behave output is being written to ${raw_log}."
  bash -o pipefail -c "${qa_command}" >"${raw_log}" 2>&1
  exit_code="$?"
fi
set -e

section "QA Result Table"
if compgen -G "${test_results_dir}/*.xml" >/dev/null; then
  python - "${test_results_dir}" <<'PY'
import os
import sys
import xml.etree.ElementTree as ET

results_dir = sys.argv[1]
rows = []
problem_rows = []
total = failed = errored = skipped = 0

def first_error_line(text):
    if not text:
        return ""
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    preferred = [
        line for line in lines
        if "selenium.common.exceptions" in line
        or line.startswith("AssertionError")
        or line.startswith("ValueError")
        or line.startswith("TimeoutException")
    ]
    return (preferred or lines)[0]

for name in sorted(os.listdir(results_dir)):
    if not name.endswith(".xml"):
        continue
    path = os.path.join(results_dir, name)
    root = ET.parse(path).getroot()
    suites = [root] if root.tag == "testsuite" else root.findall(".//testsuite")
    for suite in suites:
        total += int(suite.attrib.get("tests", 0))
        failed += int(suite.attrib.get("failures", 0))
        errored += int(suite.attrib.get("errors", 0))
        skipped += int(suite.attrib.get("skipped", 0))
    for case in root.findall(".//testcase"):
        status = "PASS"
        if case.find("error") is not None:
            status = "ERROR"
        elif case.find("failure") is not None:
            status = "FAIL"
        elif case.find("skipped") is not None:
            status = "SKIP"
        classname = case.attrib.get("classname", "")
        scenario = case.attrib.get("name", "")
        duration = case.attrib.get("time", "0")
        rows.append((status, classname, scenario, duration))
        problem = case.find("error") or case.find("failure")
        if problem is not None:
            message = problem.attrib.get("message") or first_error_line(problem.text)
            problem_rows.append((status, scenario, message))

print(f"{'Status':<8} {'Time(s)':<8} Scenario")
print(f"{'-' * 8} {'-' * 8} {'-' * 60}")
for status, classname, scenario, duration in rows:
    label = f"{classname} - {scenario}" if classname else scenario
    print(f"{status:<8} {duration:<8} {label}")

print("")
print(f"Total: {total}  Passed: {total - failed - errored - skipped}  Failed: {failed}  Errors: {errored}  Skipped: {skipped}")

if problem_rows:
    print("")
    print("Failures")
    print("--------")
    for status, scenario, message in problem_rows:
        print(f"{status}: {scenario}")
        if message:
            print(f"  {message}")
PY
else
  echo "No JUnit XML found in ${test_results_dir}."
  echo "Add these Behave options to QA_TEST_COMMAND for a clean result table:"
  echo "--junit --junit-directory ${test_results_dir}"
fi

section "QA Summary"
printf "%-12s %s\n" "Exit code:" "${exit_code}"
printf "%-12s %s\n" "Completed:" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf "%-12s %s\n" "Raw log:" "${raw_log}"
printf "%-12s %s\n" "JUnit:" "${test_results_dir}"
if [[ "${exit_code}" -eq 0 ]]; then
  echo "Status: PASS"
else
  echo "Status: FAIL"
fi

exit "${exit_code}"
