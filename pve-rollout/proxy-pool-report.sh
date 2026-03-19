#!/usr/bin/env bash

set -euo pipefail

HTTP_AVAILABLE="/etc/nginx/sites-available"
HTTP_ENABLED="/etc/nginx/sites-enabled"
STREAM_AVAILABLE="/etc/nginx/streams-available"
STREAM_ENABLED="/etc/nginx/streams-enabled"

usage() {
  cat <<EOF
Usage:
  $0 [pool|range|pool...]

Examples:
  $0
  $0 3
  $0 1 3 7
  $0 1-10
EOF
}

expand_pools() {
  local arg
  for arg in "$@"; do
    if [[ "$arg" =~ ^[0-9]+-[0-9]+$ ]]; then
      local start="${arg%-*}"
      local end="${arg#*-}"
      seq "$start" "$end"
    elif [[ "$arg" =~ ^[0-9]+$ ]]; then
      echo "$arg"
    else
      echo "Invalid pool argument: $arg" >&2
      exit 1
    fi
  done
}

print_header() {
  printf "%-6s %-8s %-8s %-8s %-8s %-16s\n" "Pool" "HTTP-A" "HTTP-E" "STR-A" "STR-E" "Status"
  printf "%-6s %-8s %-8s %-8s %-8s %-16s\n" "----" "------" "------" "------" "------" "------"
}

pool_status() {
  local pool="$1"
  local name="${pool}.bleikervgs.no"

  local http_a="no"
  local http_e="no"
  local str_a="no"
  local str_e="no"
  local status="missing"

  [[ -f "${HTTP_AVAILABLE}/${name}" ]] && http_a="yes"
  [[ -L "${HTTP_ENABLED}/${name}" ]] && http_e="yes"
  [[ -f "${STREAM_AVAILABLE}/${name}.stream.conf" ]] && str_a="yes"
  [[ -L "${STREAM_ENABLED}/${name}.stream.conf" ]] && str_e="yes"

  if [[ "$http_a" == "yes" && "$str_a" == "yes" && "$http_e" == "yes" && "$str_e" == "yes" ]]; then
    status="enabled"
  elif [[ "$http_a" == "yes" || "$str_a" == "yes" ]]; then
    if [[ "$http_e" == "yes" || "$str_e" == "yes" ]]; then
      status="partial"
    else
      status="available-only"
    fi
  fi

  printf "%-6s %-8s %-8s %-8s %-8s %-16s\n" "$pool" "$http_a" "$http_e" "$str_a" "$str_e" "$status"
}

main() {
  local pools=()

  if [[ $# -eq 0 ]]; then
    mapfile -t pools < <(
      {
        find "$HTTP_AVAILABLE" -maxdepth 1 -type f -name '*.bleikervgs.no' -printf '%f\n' 2>/dev/null | sed 's/\.bleikervgs\.no$//'
        find "$STREAM_AVAILABLE" -maxdepth 1 -type f -name '*.bleikervgs.no.stream.conf' -printf '%f\n' 2>/dev/null | sed 's/\.bleikervgs\.no\.stream\.conf$//'
      } | sort -n | uniq
    )
  else
    mapfile -t pools < <(expand_pools "$@")
  fi

  print_header

  for pool in "${pools[@]}"; do
    pool_status "$pool"
  done
}

main "$@"