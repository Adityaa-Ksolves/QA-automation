#!/usr/bin/env bash
set -euo pipefail

qa_command="${QA_TEST_COMMAND:-}"
base_requirements="${QA_BASE_REQUIREMENTS:-agent/requirements-qa-base.txt}"
pip_quiet_flag="${QA_PIP_QUIET_FLAG:---quiet}"
artifacts_dir="${QA_ARTIFACTS_DIR:-artifacts}"
log_dir="${artifacts_dir}/logs"
test_results_dir="${artifacts_dir}/test-results"
raw_log="${log_dir}/qa-raw.log"
html_report="${artifacts_dir}/Results.html"
html_css="${artifacts_dir}/Results.css"
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

rm -rf "${log_dir}" "${test_results_dir}" "${artifacts_dir}/ui-diagnostics" "${html_report}" "${html_css}"
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
printf "%-12s %s\n" "HTML:" "${html_report}"

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
  python - "${test_results_dir}" "${html_report}" "${html_css}" "${raw_log}" "${artifacts_dir}" <<'PY'
import html
import os
import sys
import xml.etree.ElementTree as ET
from datetime import datetime, timezone

results_dir = sys.argv[1]
html_report = sys.argv[2]
html_css = sys.argv[3]
raw_log = sys.argv[4]
artifacts_dir = sys.argv[5]
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

def clean_message(message):
    if not message:
        return ""
    text = str(message).replace("\r\n", "\n").replace("\r", "\n")
    if "Find element timed out" in text:
        text = text.split("Visible fields:", 1)[0].strip()
    if "Click element timed out" in text:
        text = text.split("Visible fields:", 1)[0].strip()
    if "Stacktrace:" in text:
        text = text.split("Stacktrace:", 1)[0].strip()
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    cleaned = []
    for line in lines:
        if line.startswith("Locator:") and len(line) > 180:
            cleaned.append(line[:177] + "...")
        else:
            cleaned.append(line)
    text = "\n".join(cleaned)
    if text in {"Message:", "Message", ""}:
        return "Selenium command failed. See raw log and UI diagnostics."
    return text[:900]

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
        duration = float(case.attrib.get("time", "0") or 0)
        problem = case.find("error")
        if problem is None:
            problem = case.find("failure")
        message = ""
        if problem is not None:
            message = problem.attrib.get("message") or first_error_line(problem.text)
            message = clean_message(message)
            problem_rows.append((status, scenario, message))
        rows.append((status, classname, scenario, duration, message))

print(f"{'Status':<8} {'Time(s)':<8} Scenario")
print(f"{'-' * 8} {'-' * 8} {'-' * 60}")
for status, classname, scenario, duration, _message in rows:
    label = f"{classname} - {scenario}" if classname else scenario
    print(f"{status:<8} {duration:<8.2f} {label}")

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

def rel(path):
    return html.escape(os.path.relpath(path, artifacts_dir))

def diagnostic_links():
    diag_dir = os.path.join(artifacts_dir, "ui-diagnostics")
    if not os.path.isdir(diag_dir):
        return []
    files = []
    for name in sorted(os.listdir(diag_dir)):
        path = os.path.join(diag_dir, name)
        if name.endswith(".png"):
            files.append(("Screenshot", path))
        elif name.endswith(".html"):
            files.append(("Page HTML", path))
    return files

def status_class(status):
    return {
        "PASS": "pass",
        "FAIL": "fail",
        "ERROR": "error",
        "SKIP": "skip",
    }.get(status, "unknown")

def scenario_title(scenario):
    return scenario.split(" -- @", 1)[0].strip()

def scenario_case(scenario):
    if " -- @" in scenario:
        return "@" + scenario.split(" -- @", 1)[1].strip()
    return ""

def linked_artifact(value):
    normalized = value.strip()
    if normalized.startswith("artifacts/"):
        normalized = normalized[len("artifacts/"):]
    path = os.path.join(artifacts_dir, normalized)
    if os.path.exists(path):
        return f"<a href='{rel(path)}'>{html.escape(os.path.basename(path))}</a>"
    return html.escape(value)

def failure_detail_html(message):
    if not message:
        return "<p class='muted'>No failure detail was captured. Open the raw log for the full traceback.</p>"
    lines = [line.strip() for line in message.splitlines() if line.strip()]
    if not lines:
        return "<p class='muted'>No failure detail was captured. Open the raw log for the full traceback.</p>"

    summary = html.escape(lines[0])
    detail_rows = []
    for line in lines[1:]:
        if ":" not in line:
            detail_rows.append(f"<div class='detail-row'><div class='detail-key'>Detail</div><div class='detail-value'>{html.escape(line)}</div></div>")
            continue
        key, value = line.split(":", 1)
        key = key.strip()
        value = value.strip()
        rendered_value = linked_artifact(value) if key in {"Screenshot", "HTML"} else html.escape(value)
        detail_rows.append(f"<div class='detail-row'><div class='detail-key'>{html.escape(key)}</div><div class='detail-value'>{rendered_value}</div></div>")

    if not detail_rows:
        return f"<p class='failure-summary'>{summary}</p>"
    return f"<p class='failure-summary'>{summary}</p><div class='failure-details'>{''.join(detail_rows)}</div>"

passed = total - failed - errored - skipped
completed = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
diagnostics = diagnostic_links()
run_status = "PASS" if failed == 0 and errored == 0 else "FAIL"
run_status_class = "pass" if run_status == "PASS" else "fail"

rows_html = []
for status, classname, scenario, duration, message in rows:
    title = scenario_title(scenario)
    case_id = scenario_case(scenario)
    failure_cell = ""
    if message:
        failure_cell = "<a class='action-link' href='#failures'>View failure</a>"
    rows_html.append(
        "<tr>"
        f"<td><span class='badge {status_class(status)}'>{html.escape(status)}</span></td>"
        f"<td>{duration:.2f}</td>"
        "<td>"
        f"<div class='scenario-title'>{html.escape(title)}</div>"
        f"<div class='scenario-meta'>{html.escape(classname)}"
        f"{' | ' + html.escape(case_id) if case_id else ''}</div>"
        "</td>"
        f"<td>{failure_cell}</td>"
        "</tr>"
    )

failures_html = ""
if problem_rows:
    items = []
    for status, scenario, message in problem_rows:
        title = scenario_title(scenario)
        case_id = scenario_case(scenario)
        items.append(
            f"<article class='failure-card {status_class(status)}-border'>"
            f"<div class='failure-heading'><span class='badge {status_class(status)}'>{html.escape(status)}</span>"
            f"<div><strong>{html.escape(title)}</strong>"
            f"<div class='scenario-meta'>{html.escape(case_id)}</div></div></div>"
            f"{failure_detail_html(message)}"
            "</article>"
        )
    failures_html = "<section id='failures' class='panel'><h2>Failures</h2>" + "\n".join(items) + "</section>"

diagnostics_html = ""
if diagnostics:
    links = "\n".join(
        f"<a class='diag-link' href='{rel(path)}'><span>{html.escape(kind)}</span><small>{html.escape(os.path.basename(path))}</small></a>"
        for kind, path in diagnostics
    )
    diagnostics_html = f"<section class='panel'><h2>UI Diagnostics</h2><div class='diag-grid'>{links}</div></section>"

stylesheet = """body {
  margin: 0;
  color: #17202a;
  background: #f4f7fa;
  font-family: Arial, Helvetica, sans-serif;
}
.page {
  max-width: 1280px;
  margin: 0 auto;
  padding: 24px;
}
.header {
  background: #ffffff;
  border: 1px solid #d8dee4;
  border-radius: 8px;
  padding: 22px 24px;
  margin-bottom: 18px;
  display: flex;
  justify-content: space-between;
  gap: 16px;
  align-items: flex-start;
}
.details-grid {
  display: grid;
  grid-template-columns: 180px 1fr;
  background: #ffffff;
  border: 1px solid #d8dee4;
  border-radius: 8px;
  overflow: hidden;
}
.details-key, .details-value {
  padding: 12px 14px;
  border-bottom: 1px solid #e5e8eb;
}
.details-key {
  background: #eef2f6;
  color: #1f3a5f;
  font-weight: 700;
  font-size: 13px;
}
.details-value {
  background: #ffffff;
}
.details-key:nth-last-child(2), .details-value:last-child {
  border-bottom: 0;
}
h1 {
  margin: 0 0 6px;
  font-size: 28px;
}
h2 {
  margin: 28px 0 12px;
  font-size: 20px;
}
.meta {
  color: #5d6d7e;
}
.run-status {
  text-align: right;
}
.run-status .badge {
  min-width: 72px;
  font-size: 13px;
}
.summary {
  display: grid;
  grid-template-columns: repeat(5, minmax(130px, 1fr));
  gap: 12px;
  margin: 18px 0;
}
.card {
  background: #ffffff;
  border: 1px solid #d8dee4;
  border-radius: 8px;
  padding: 16px;
}
.card.pass-card {
  border-left: 5px solid #2ecc71;
}
.card.fail-card {
  border-left: 5px solid #e74c3c;
}
.card.error-card {
  border-left: 5px solid #c0392b;
}
.card.skip-card {
  border-left: 5px solid #95a5a6;
}
.label {
  color: #5d6d7e;
  font-size: 12px;
  text-transform: uppercase;
  letter-spacing: .04em;
}
.value {
  font-size: 28px;
  font-weight: 700;
  margin-top: 4px;
}
table {
  width: 100%;
  border-collapse: collapse;
  background: #ffffff;
  border: 1px solid #d8dee4;
  border-radius: 8px;
  overflow: hidden;
}
th, td {
  text-align: left;
  border-bottom: 1px solid #e5e8eb;
  padding: 11px 12px;
  vertical-align: top;
}
th {
  background: #eef2f6;
  color: #34495e;
  font-size: 13px;
}
tr:last-child td {
  border-bottom: 0;
}
td:first-child {
  width: 86px;
}
td:nth-child(2) {
  width: 78px;
  white-space: nowrap;
}
td:last-child {
  width: 110px;
}
td:nth-child(3) {
  line-height: 1.35;
}
.scenario-title {
  font-weight: 600;
}
.scenario-meta {
  color: #6b7c8f;
  font-size: 12px;
  margin-top: 4px;
}
.panel {
  margin-top: 24px;
}
.badge {
  display: inline-block;
  min-width: 58px;
  text-align: center;
  border-radius: 999px;
  padding: 4px 9px;
  font-size: 12px;
  font-weight: 700;
}
.pass {
  background: #d5f5e3;
  color: #145a32;
}
.fail, .error {
  background: #fadbd8;
  color: #922b21;
}
.skip {
  background: #eaeded;
  color: #566573;
}
pre {
  white-space: pre-wrap;
  background: #f8fafc;
  border: 1px solid #d8dee4;
  border-radius: 6px;
  padding: 10px;
  overflow-x: auto;
  line-height: 1.45;
  margin: 10px 0 0;
}
.muted {
  color: #6b7c8f;
}
.failure-summary {
  margin: 12px 0 10px;
  font-weight: 600;
}
.failure-details {
  display: grid;
  grid-template-columns: 140px 1fr;
  background: #f8fafc;
  border: 1px solid #d8dee4;
  border-radius: 6px;
  overflow: hidden;
}
.detail-key, .detail-value {
  padding: 8px 10px;
  border-bottom: 1px solid #e5e8eb;
}
.detail-key {
  background: #eef2f6;
  color: #34495e;
  font-weight: 700;
  font-size: 12px;
}
.detail-value {
  overflow-wrap: anywhere;
}
.detail-key:nth-last-child(2), .detail-value:last-child {
  border-bottom: 0;
}
a {
  color: #1f618d;
  text-decoration: none;
}
a:hover {
  text-decoration: underline;
}
.action-link {
  display: inline-block;
  border: 1px solid #b6d4ea;
  background: #eef7ff;
  border-radius: 6px;
  padding: 6px 9px;
  font-size: 13px;
  font-weight: 700;
}
.failure-card, .diag-grid {
  background: #ffffff;
  border: 1px solid #d8dee4;
  border-radius: 8px;
  padding: 14px;
}
.failure-card {
  margin-bottom: 12px;
}
.failure-card.fail-border {
  border-left: 5px solid #e74c3c;
}
.failure-card.error-border {
  border-left: 5px solid #c0392b;
}
.failure-heading {
  display: flex;
  align-items: center;
  gap: 10px;
}
.diag-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(320px, 1fr));
  gap: 8px;
}
.diag-link {
  display: block;
  background: #f8fafc;
  border: 1px solid #e5e8eb;
  border-radius: 6px;
  padding: 10px;
  overflow-wrap: anywhere;
}
.diag-link span {
  display: block;
  font-weight: 700;
  color: #1f3a5f;
}
.diag-link small {
  display: block;
  color: #6b7c8f;
  margin-top: 4px;
}
@media (max-width: 800px) {
  .page {
    padding: 14px;
  }
  .header {
    display: block;
  }
  .run-status {
    text-align: left;
    margin-top: 12px;
  }
  .summary {
    grid-template-columns: repeat(2, minmax(120px, 1fr));
  }
  .failure-details {
    grid-template-columns: 1fr;
  }
  .detail-key {
    border-bottom: 0;
  }
}
"""

with open(html_css, "w", encoding="utf-8") as handle:
    handle.write(stylesheet)

report = f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>QA Results</title>
  <link rel="stylesheet" href="{rel(html_css)}">
</head>
<body>
  <main class="page">
    <section class="header">
      <div>
        <h1>QA Results</h1>
        <div class="meta">Generated {html.escape(completed)} for customer {html.escape(os.environ.get("CUSTOMER", "unknown"))}</div>
      </div>
      <div class="run-status">
        <div class="label">Run Status</div>
        <span class="badge {run_status_class}">{run_status}</span>
      </div>
    </section>
    <section class="summary">
      <div class="card"><div class="label">Total</div><div class="value">{total}</div></div>
      <div class="card pass-card"><div class="label">Passed</div><div class="value">{passed}</div></div>
      <div class="card fail-card"><div class="label">Failed</div><div class="value">{failed}</div></div>
      <div class="card error-card"><div class="label">Errors</div><div class="value">{errored}</div></div>
      <div class="card skip-card"><div class="label">Skipped</div><div class="value">{skipped}</div></div>
    </section>
    <section class="panel">
      <h2>Run Details</h2>
      <div class="details-grid">
        <div class="details-key">Customer</div><div class="details-value">{html.escape(os.environ.get("CUSTOMER", "unknown"))}</div>
        <div class="details-key">Target URL</div><div class="details-value">{html.escape(os.environ.get("TARGET_URL", ""))}</div>
        <div class="details-key">Browser</div><div class="details-value">{html.escape(os.environ.get("BROWSER", ""))}</div>
        <div class="details-key">Tags</div><div class="details-value">{html.escape(os.environ.get("TEST_TAGS", ""))}</div>
        <div class="details-key">Raw Log</div><div class="details-value"><a href="{rel(raw_log)}">{rel(raw_log)}</a></div>
      </div>
    </section>
    <section class="panel">
      <h2>Scenarios</h2>
      <table>
        <thead><tr><th>Status</th><th>Time(s)</th><th>Scenario</th><th>Failure</th></tr></thead>
        <tbody>
          {"".join(rows_html)}
        </tbody>
      </table>
    </section>
    {failures_html}
    {diagnostics_html}
  </main>
</body>
</html>
"""

with open(html_report, "w", encoding="utf-8") as handle:
    handle.write(report)

print("")
print(f"HTML report: {html_report}")
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
printf "%-12s %s\n" "HTML:" "${html_report}"
if [[ "${exit_code}" -eq 0 ]]; then
  echo "Status: PASS"
else
  echo "Status: FAIL"
fi

exit "${exit_code}"
