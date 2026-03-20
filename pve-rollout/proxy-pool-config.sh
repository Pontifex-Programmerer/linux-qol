#!/usr/bin/env bash

set -euo pipefail

HTTP_OUTPUT_DIR="/etc/nginx/sites-available"
STREAM_OUTPUT_DIR="/etc/nginx/streams-available"

DRY_RUN=false
OVERWRITE=false
FORCE=false

ACTION=""
START_POOL=""
END_POOL=""
HOST_OCTET="20"
NETWORK_PREFIX="10.14"

usage() {
  cat <<EOF
proxy-pool-config.sh

Create or remove nginx pool configuration files.

USAGE:
  $0 <create|remove> --start <pool> --end <pool> [options]

EXAMPLES:
  $0 create --start 1 --end 10
  $0 create --start 1 --end 10 --overwrite
  $0 create --start 99 --end 99 --dry-run
  $0 remove --start 1 --end 10
  $0 remove --start 1 --end 10 --dry-run

REQUIRED:
  create|remove               Action to perform
  --start <n>                 Start pool number
  --end <n>                   End pool number

OPTIONS:
  --host-octet <n>            Backend host octet (default: 20)
  --network-prefix <x.y>      Network prefix (default: 10.14)

  --http-output-dir <path>    HTTP config output dir
                              (default: /etc/nginx/sites-available)
  --stream-output-dir <path>  Stream config output dir
                              (default: /etc/nginx/streams-available)

  --overwrite                 Overwrite existing files when using create
  --force                     Reserved for future use
  --dry-run                   Print what would be done (no changes)
  -h, --help                  Show this help

NOTES:
  - create writes files to the "available" directories only
  - remove deletes files from the "available" directories only
  - enabling/disabling is handled separately by proxy-pool-enable.sh
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    create|remove) ACTION="$1"; shift ;;
    --start) START_POOL="$2"; shift 2 ;;
    --end) END_POOL="$2"; shift 2 ;;
    --host-octet) HOST_OCTET="$2"; shift 2 ;;
    --network-prefix) NETWORK_PREFIX="$2"; shift 2 ;;
    --http-output-dir) HTTP_OUTPUT_DIR="$2"; shift 2 ;;
    --stream-output-dir) STREAM_OUTPUT_DIR="$2"; shift 2 ;;
    --overwrite) OVERWRITE=true; shift ;;
    --force) FORCE=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1"; usage; exit 1 ;;
  esac
done

if [[ -z "$ACTION" ]]; then
  echo "Error: action is required (create|remove)."
  usage
  exit 1
fi

if [[ -z "$START_POOL" || -z "$END_POOL" ]]; then
  echo "Error: --start and --end are required."
  usage
  exit 1
fi

if [[ "$DRY_RUN" == false ]]; then
  mkdir -p "$HTTP_OUTPUT_DIR"
  mkdir -p "$STREAM_OUTPUT_DIR"
fi

create_pool() {
  local pool="$1"
  local domain="${pool}.bleikervgs.no"
  local backend_ip="${NETWORK_PREFIX}.${pool}.${HOST_OCTET}"

  local http_filename="${domain}"
  local http_filepath="${HTTP_OUTPUT_DIR}/${http_filename}"

  local stream_filename="${domain}.stream.conf"
  local stream_filepath="${STREAM_OUTPUT_DIR}/${stream_filename}"

  local write_http=true
  local write_stream=true

  if [[ "$OVERWRITE" != true ]]; then
    if [[ -e "$http_filepath" ]]; then
      echo "Skipping existing HTTP file: $http_filepath"
      write_http=false
    fi

    if [[ -e "$stream_filepath" ]]; then
      echo "Skipping existing stream file: $stream_filepath"
      write_stream=false
    fi
  fi

  if [[ "$write_http" == false && "$write_stream" == false ]]; then
    return 0
  fi

  local http_config
  http_config=$(cat <<EOF
server {
    listen 80;
    server_name ${domain} *.${domain};

    location / {
        proxy_pass http://${backend_ip}:80;
        proxy_http_version 1.1;

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF
)

  local stream_config
  stream_config=$(cat <<EOF
# ${domain}
${domain} ${backend_ip}:443;
*.${domain} ${backend_ip}:443;
EOF
)

  if [[ "$DRY_RUN" == true ]]; then
    if [[ "$write_http" == true ]]; then
      echo "----- CREATE HTTP: ${http_filepath} -----"
      echo "$http_config"
      echo
    fi

    if [[ "$write_stream" == true ]]; then
      echo "----- CREATE STREAM: ${stream_filepath} -----"
      echo "$stream_config"
      echo
    fi
  else
    if [[ "$write_http" == true ]]; then
      echo "$http_config" > "$http_filepath"
      echo "Wrote HTTP config: $http_filepath"
    fi

    if [[ "$write_stream" == true ]]; then
      echo "$stream_config" > "$stream_filepath"
      echo "Wrote stream config: $stream_filepath"
    fi
  fi
}

remove_pool() {
  local pool="$1"
  local domain="${pool}.bleikervgs.no"

  local http_filepath="${HTTP_OUTPUT_DIR}/${domain}"
  local stream_filepath="${STREAM_OUTPUT_DIR}/${domain}.stream.conf"

  if [[ "$DRY_RUN" == true ]]; then
    [[ -e "$http_filepath" ]] && echo "Would remove HTTP config:   $http_filepath"
    [[ -e "$stream_filepath" ]] && echo "Would remove stream config: $stream_filepath"
    return 0
  fi

  [[ -e "$http_filepath" ]] && rm -f "$http_filepath" && echo "Removed HTTP config: $http_filepath"
  [[ -e "$stream_filepath" ]] && rm -f "$stream_filepath" && echo "Removed stream config: $stream_filepath"
}

for pool in $(seq "$START_POOL" "$END_POOL"); do
  case "$ACTION" in
    create) create_pool "$pool" ;;
    remove) remove_pool "$pool" ;;
  esac
done

echo
if [[ "$DRY_RUN" == true ]]; then
  echo "Dry run complete. No changes made."
else
  case "$ACTION" in
    create)
      echo "Create complete."
      echo "Remember:"
      echo "  1. HTTP configs are in:        $HTTP_OUTPUT_DIR"
      echo "  2. Stream configs are in:      $STREAM_OUTPUT_DIR"
      echo "  3. Enable configs separately with proxy-pool-enable.sh"
      ;;
    remove)
      echo "Remove complete."
      echo "Remember:"
      echo "  1. This only removed files from the available directories"
      echo "  2. Disable symlinks separately with proxy-pool-enable.sh if needed"
      ;;
  esac
  echo "  3. Test nginx before reload:"
  echo "     sudo nginx -t && sudo systemctl reload nginx"
fi