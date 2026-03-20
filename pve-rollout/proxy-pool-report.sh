#!/usr/bin/env bash

set -euo pipefail

HTTP_AVAILABLE="/etc/nginx/sites-available"
HTTP_ENABLED="/etc/nginx/sites-enabled"
STREAM_AVAILABLE="/etc/nginx/streams-available"
STREAM_ENABLED="/etc/nginx/streams-enabled"

FILTER="all"
SHOW_HEADER=true
SHOW_SUMMARY=false

usage() {
  cat <<EOF
proxy-pool-report.sh

Shows status of proxy configuration per pool.

USAGE:
  $0 [options] [pool|range...]

EXAMPLES:
  $0
  $0 3
  $0 1-10
  $0 --enabled
  $0 --partial 1-20
  $0 --missing 1-100
  $0 --summary
  $0 --enabled --no-header

FILTER OPTIONS:
  --enabled     Show only fully enabled pools
  --available   Show pools with config but not enabled
  --partial     Show partially configured/enabled pools
  --missing     Show pools with no config

OUTPUT OPTIONS:
  --no-header   Do not print the table header
  --summary     Print summary counts after the table

COLUMNS:
  Pool     Pool number
  HTTP-A   HTTP config exists in sites-available
  HTTP-E   HTTP config enabled (symlink in sites-enabled)
  STR-A    Stream config exists in streams-available
  STR-E    Stream config enabled (symlink in streams-enabled)

STATUS VALUES:
  enabled
    - HTTP and STREAM configs exist AND are enabled

  partial
    - Some configs exist and/or are enabled, but not all

  available-only
    - Config exists, but nothing is enabled

  missing
    - No config exists for this pool

NOTES:
  - HTTP refers to port 80 reverse proxy
  - STREAM refers to port 443 TLS passthrough (SNI routing)
  - When no pools are provided, the script auto-discovers pools from both
    available and enabled directories
  - --missing is most useful together with an explicit pool or range, for example:
      $0 --missing 1-100
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

get_status() {
  local http_a="$1"
  local http_e="$2"
  local str_a="$3"
  local str_e="$4"

  if [[ "$http_a" == "yes" && "$str_a" == "yes" && "$http_e" == "yes" && "$str_e" == "yes" ]]; then
    echo "enabled"
  elif [[ "$http_a" == "yes" || "$str_a" == "yes" || "$http_e" == "yes" || "$str_e" == "yes" ]]; then
    if [[ "$http_e" == "yes" || "$str_e" == "yes" ]]; then
      echo "partial"
    else
      echo "available-only"
    fi
  else
    echo "missing"
  fi
}

matches_filter() {
  local status="$1"

  case "$FILTER" in
    all) return 0 ;;
    enabled) [[ "$status" == "enabled" ]] ;;
    partial) [[ "$status" == "partial" ]] ;;
    available) [[ "$status" == "available-only" ]] ;;
    missing) [[ "$status" == "missing" ]] ;;
  esac
}

ENABLED_COUNT=0
PARTIAL_COUNT=0
AVAILABLE_ONLY_COUNT=0
MISSING_COUNT=0

count_status() {
  local status="$1"
  case "$status" in
    enabled) ((ENABLED_COUNT+=1)) ;;
    partial) ((PARTIAL_COUNT+=1)) ;;
    available-only) ((AVAILABLE_ONLY_COUNT+=1)) ;;
    missing) ((MISSING_COUNT+=1)) ;;
  esac
}

pool_status() {
  local pool="$1"
  local name="${pool}.bleikervgs.no"

  local http_a="no"
  local http_e="no"
  local str_a="no"
  local str_e="no"

  [[ -f "${HTTP_AVAILABLE}/${name}" ]] && http_a="yes"
  [[ -L "${HTTP_ENABLED}/${name}" ]] && http_e="yes"
  [[ -f "${STREAM_AVAILABLE}/${name}.stream.conf" ]] && str_a="yes"
  [[ -L "${STREAM_ENABLED}/${name}.stream.conf" ]] && str_e="yes"

  local status
  status=$(get_status "$http_a" "$http_e" "$str_a" "$str_e")

  count_status "$status"

  if matches_filter "$status"; then
    printf "%-6s %-8s %-8s %-8s %-8s %-16s\n" "$pool" "$http_a" "$http_e" "$str_a" "$str_e" "$status"
  fi
}

discover_pools() {
  {
    find "$HTTP_AVAILABLE"  -maxdepth 1 \( -type f -o -type l \) -name '*.bleikervgs.no'            -printf '%f\n' 2>/dev/null | sed 's/\.bleikervgs\.no$//'
    find "$HTTP_ENABLED"    -maxdepth 1 \( -type f -o -type l \) -name '*.bleikervgs.no'            -printf '%f\n' 2>/dev/null | sed 's/\.bleikervgs\.no$//'
    find "$STREAM_AVAILABLE" -maxdepth 1 \( -type f -o -type l \) -name '*.bleikervgs.no.stream.conf' -printf '%f\n' 2>/dev/null | sed 's/\.bleikervgs\.no\.stream\.conf$//'
    find "$STREAM_ENABLED"   -maxdepth 1 \( -type f -o -type l \) -name '*.bleikervgs.no.stream.conf' -printf '%f\n' 2>/dev/null | sed 's/\.bleikervgs\.no\.stream\.conf$//'
  } | sort -n | uniq
}

print_summary() {
  echo
  echo "Summary:"
  echo "  enabled:         $ENABLED_COUNT"
  echo "  partial:         $PARTIAL_COUNT"
  echo "  available-only:  $AVAILABLE_ONLY_COUNT"
  echo "  missing:         $MISSING_COUNT"
}

main() {
  local args=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --enabled) FILTER="enabled"; shift ;;
      --partial) FILTER="partial"; shift ;;
      --available) FILTER="available"; shift ;;
      --missing) FILTER="missing"; shift ;;
      --no-header) SHOW_HEADER=false; shift ;;
      --summary) SHOW_SUMMARY=true; shift ;;
      -h|--help) usage; exit 0 ;;
      *) args+=("$1"); shift ;;
    esac
  done

  local pools=()

  if [[ ${#args[@]} -eq 0 ]]; then
    mapfile -t pools < <(discover_pools)
  else
    mapfile -t pools < <(expand_pools "${args[@]}")
  fi

  if [[ "$SHOW_HEADER" == true ]]; then
    print_header
  fi

  for pool in "${pools[@]}"; do
    pool_status "$pool"
  done

  if [[ "$SHOW_SUMMARY" == true ]]; then
    print_summary
  fi
}

main "$@"