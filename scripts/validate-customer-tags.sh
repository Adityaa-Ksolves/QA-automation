#!/usr/bin/env bash
set -euo pipefail

feature_file="${1:-}"

if [[ -z "${feature_file}" ]]; then
  echo "Usage: $0 <path-to-synthetic-monitoring.feature>" >&2
  exit 2
fi

if [[ ! -f "${feature_file}" ]]; then
  echo "Feature file not found: ${feature_file}" >&2
  exit 2
fi

required_tags=(
  "@customer_piedmont"
  "@customer_zito"
  "@customer_brctv"
  "@customer_comporium"
  "@customer_sectv"
  "@customer_secv"
  "@customer_wow_trial"
)

missing=0

has_active_tag() {
  local tag="$1"
  grep -Ev '^[[:space:]]*#' "${feature_file}" | grep -Eq "(^|[[:space:]])${tag}($|[[:space:]])"
}

if ! has_active_tag "@synthetic_monitoring"; then
  echo "Missing required feature tag: @synthetic_monitoring" >&2
  missing=1
fi

for tag in "${required_tags[@]}"; do
  if ! has_active_tag "${tag}"; then
    echo "Missing required customer tag: ${tag}" >&2
    missing=1
  fi
done

if [[ "${missing}" -ne 0 ]]; then
  echo "Customer tag validation failed." >&2
  exit 1
fi

echo "Customer tag validation passed for ${feature_file}."
