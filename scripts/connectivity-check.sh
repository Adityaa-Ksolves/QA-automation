#!/usr/bin/env bash
set -euo pipefail

target_url="${1:-}"
artifact_dir="${WORKSPACE_ARTIFACT_DIR:-artifacts}/connectivity"

if [[ -z "${target_url}" ]]; then
  echo "Usage: $0 <target-url>" >&2
  exit 2
fi

mkdir -p "${artifact_dir}"

python_url_parser='
import sys
from urllib.parse import urlparse
url = sys.argv[1]
parsed = urlparse(url)
if not parsed.scheme or not parsed.hostname:
    raise SystemExit("Invalid URL: %s" % url)
port = parsed.port or (443 if parsed.scheme == "https" else 80)
print(parsed.scheme)
print(parsed.hostname)
print(port)
'

mapfile -t parsed < <(python3 -c "${python_url_parser}" "${target_url}")
scheme="${parsed[0]}"
host="${parsed[1]}"
port="${parsed[2]}"

summary_file="${artifact_dir}/summary.txt"
http_headers_file="${artifact_dir}/http-headers.txt"
tls_file="${artifact_dir}/tls.txt"

{
  echo "target_url=${target_url}"
  echo "scheme=${scheme}"
  echo "host=${host}"
  echo "port=${port}"
  echo "node=${NODE_NAME:-unknown}"
  echo "customer=${CUSTOMER:-unknown}"
  echo "started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "${summary_file}"

echo "Checking DNS for ${host}"
if command -v dig >/dev/null 2>&1; then
  dig +short "${host}" | tee "${artifact_dir}/dns.txt"
else
  getent hosts "${host}" | tee "${artifact_dir}/dns.txt"
fi

if [[ ! -s "${artifact_dir}/dns.txt" ]]; then
  echo "DNS lookup failed for ${host}" | tee -a "${summary_file}"
  exit 10
fi

echo "Checking TCP connectivity to ${host}:${port}"
if ! nc -vz -w 10 "${host}" "${port}" 2>&1 | tee "${artifact_dir}/tcp.txt"; then
  echo "TCP connectivity failed for ${host}:${port}" | tee -a "${summary_file}"
  exit 11
fi

if [[ "${scheme}" == "https" ]]; then
  echo "Checking TLS handshake for ${host}:${port}"
  if ! timeout 20 openssl s_client -connect "${host}:${port}" -servername "${host}" </dev/null >"${tls_file}" 2>&1; then
    echo "TLS handshake failed for ${host}:${port}" | tee -a "${summary_file}"
    exit 12
  fi
fi

echo "Checking HTTP response for ${target_url}"
http_code="$(
  curl \
    --location \
    --insecure \
    --silent \
    --show-error \
    --output /dev/null \
    --dump-header "${http_headers_file}" \
    --write-out "%{http_code}" \
    --connect-timeout 15 \
    --max-time 60 \
    "${target_url}"
)"

echo "http_code=${http_code}" | tee -a "${summary_file}"

case "${http_code}" in
  200|201|202|204|301|302|303|307|308|401|403)
    echo "Connectivity check passed" | tee -a "${summary_file}"
    ;;
  *)
    echo "Unexpected HTTP response ${http_code}" | tee -a "${summary_file}"
    exit 13
    ;;
esac

echo "completed_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "${summary_file}"
