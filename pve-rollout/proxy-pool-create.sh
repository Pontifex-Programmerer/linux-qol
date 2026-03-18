#!/usr/bin/env bash

set -euo pipefail

START_POOL=""
END_POOL=""
HOST_OCTET="20"
NETWORK_PREFIX="10.14"
OUTPUT_DIR="/etc/nginx/sites-available"
ENABLE_DIR="/etc/nginx/sites-enabled"
OVERWRITE=false
ENABLE=false
DRY_RUN=false

usage() {
  cat <<EOF
Usage: $0 --start <pool> --end <pool> [options]

Required:
  --start <n>             Start pool number
  --end <n>               End pool number

Options:
  --host-octet <n>        Backend host octet (default: 20)
  --network-prefix <x.y>  Network prefix (default: 10.14)
  --output-dir <path>     Output directory
  --enable-dir <path>     Enable directory (default: /etc/nginx/sites-enabled)
  --enable                Create symlinks in sites-enabled
  --overwrite             Overwrite existing files
  --dry-run               Print what would be done (no changes)
  -h, --help              Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --start) START_POOL="$2"; shift 2 ;;
    --end) END_POOL="$2"; shift 2 ;;
    --host-octet) HOST_OCTET="$2"; shift 2 ;;
    --network-prefix) NETWORK_PREFIX="$2"; shift 2 ;;
    --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
    --enable-dir) ENABLE_DIR="$2"; shift 2 ;;
    --overwrite) OVERWRITE=true; shift ;;
    --enable) ENABLE=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1"; usage; exit 1 ;;
  esac
done

if [[ -z "$START_POOL" || -z "$END_POOL" ]]; then
  echo "Error: --start and --end are required."
  usage
  exit 1
fi

if [[ "$DRY_RUN" == false ]]; then
  mkdir -p "$OUTPUT_DIR"
  [[ "$ENABLE" == true ]] && mkdir -p "$ENABLE_DIR"
fi

for pool in $(seq "$START_POOL" "$END_POOL"); do
  filename="${pool}.bleikervgs.no"
  filepath="${OUTPUT_DIR}/${filename}"
  backend_ip="${NETWORK_PREFIX}.${pool}.${HOST_OCTET}"

  if [[ -e "$filepath" && "$OVERWRITE" != true ]]; then
    echo "Skipping existing file: $filepath"
    continue
  fi

  config=$(cat <<EOF
server {
    listen 80;
    server_name ${pool}.bleikervgs.no;

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

  if [[ "$DRY_RUN" == true ]]; then
    echo "----- ${filepath} -----"
    echo "$config"
    echo
  else
    echo "$config" > "$filepath"
    echo "Wrote: $filepath"

    if [[ "$ENABLE" == true ]]; then
      ln -sfn "$filepath" "${ENABLE_DIR}/${filename}"
      echo "Enabled: ${ENABLE_DIR}/${filename}"
    fi
  fi
done

echo
if [[ "$DRY_RUN" == true ]]; then
  echo "Dry run complete. No changes made."
else
  echo "Done."
  echo "Run: sudo nginx -t && sudo systemctl reload nginx"
fi