#!/usr/bin/env bash

set -euo pipefail

HTTP_AVAILABLE="/etc/nginx/sites-available"
HTTP_ENABLED="/etc/nginx/sites-enabled"

STREAM_AVAILABLE="/etc/nginx/streams-available"
STREAM_ENABLED="/etc/nginx/streams-enabled"

DRY_RUN=false
NO_RELOAD=false

usage() {
  cat <<EOF
Usage:
  $0 <enable|disable|status> <pool|range|pool...> [options]

Examples:
  $0 enable 3
  $0 disable 3
  $0 enable 1-10
  $0 enable 3 5 7
  $0 status 3
  $0 enable 1-5 --dry-run

Options:
  --dry-run     Show what would be done
  --no-reload   Do not run nginx -t / reload
  -h, --help    Show this help
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

do_enable() {
  local pool="$1"
  local name="${pool}.bleikervgs.no"

  local http_src="${HTTP_AVAILABLE}/${name}"
  local http_dst="${HTTP_ENABLED}/${name}"

  local stream_src="${STREAM_AVAILABLE}/${name}.stream.conf"
  local stream_dst="${STREAM_ENABLED}/${name}.stream.conf"

  [[ -f "$http_src" ]] || { echo "Missing HTTP config: $http_src"; return 1; }
  [[ -f "$stream_src" ]] || { echo "Missing stream config: $stream_src"; return 1; }

  if [[ "$DRY_RUN" == true ]]; then
    echo "Would enable HTTP:   $http_dst -> $http_src"
    echo "Would enable STREAM: $stream_dst -> $stream_src"
  else
    ln -sfn "$http_src" "$http_dst"
    ln -sfn "$stream_src" "$stream_dst"
    echo "Enabled pool $pool"
  fi
}

do_disable() {
  local pool="$1"
  local name="${pool}.bleikervgs.no"

  local http_dst="${HTTP_ENABLED}/${name}"
  local stream_dst="${STREAM_ENABLED}/${name}.conf"

  if [[ "$DRY_RUN" == true ]]; then
    [[ -L "$http_dst" ]] && echo "Would remove HTTP symlink:   $http_dst"
    [[ -L "$stream_dst" ]] && echo "Would remove STREAM symlink: $stream_dst"
  else
    [[ -L "$http_dst" ]] && rm -f "$http_dst"
    [[ -L "$stream_dst" ]] && rm -f "$stream_dst"
    echo "Disabled pool $pool"
  fi
}

do_status() {
  local pool="$1"
  local name="${pool}.bleikervgs.no"

  local http_src="${HTTP_AVAILABLE}/${name}"
  local http_dst="${HTTP_ENABLED}/${name}"

  local stream_src="${STREAM_AVAILABLE}/${name}.conf"
  local stream_dst="${STREAM_ENABLED}/${name}.conf"

  echo "Pool $pool"
  [[ -f "$http_src" ]] && echo "  HTTP available:   yes" || echo "  HTTP available:   no"
  [[ -L "$http_dst" ]] && echo "  HTTP enabled:     yes" || echo "  HTTP enabled:     no"
  [[ -f "$stream_src" ]] && echo "  STREAM available: yes" || echo "  STREAM available: no"
  [[ -L "$stream_dst" ]] && echo "  STREAM enabled:   yes" || echo "  STREAM enabled:   no"
}

reload_nginx() {
  if [[ "$DRY_RUN" == true || "$NO_RELOAD" == true ]]; then
    return
  fi

  nginx -t
  systemctl reload nginx
  echo "Nginx reloaded"
}

main() {
  [[ $# -ge 2 ]] || { usage; exit 1; }

  local action="$1"
  shift

  local args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run) DRY_RUN=true; shift ;;
      --no-reload) NO_RELOAD=true; shift ;;
      -h|--help) usage; exit 0 ;;
      *) args+=("$1"); shift ;;
    esac
  done

  mkdir -p "$HTTP_ENABLED" "$STREAM_ENABLED"

  mapfile -t pools < <(expand_pools "${args[@]}")

  case "$action" in
    enable)
      for pool in "${pools[@]}"; do
        do_enable "$pool"
      done
      reload_nginx
      ;;
    disable)
      for pool in "${pools[@]}"; do
        do_disable "$pool"
      done
      reload_nginx
      ;;
    status)
      for pool in "${pools[@]}"; do
        do_status "$pool"
      done
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"