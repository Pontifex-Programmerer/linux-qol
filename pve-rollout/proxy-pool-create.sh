#!/usr/bin/env bash

set -euo pipefail

START_POOL=""
END_POOL=""
HOST_OCTET="20"
NETWORK_PREFIX="10.14"

HTTP_OUTPUT_DIR="/etc/nginx/sites-available"
STREAM_OUTPUT_DIR="/etc/nginx/streams-available"

OVERWRITE=false
DRY_RUN=false

usage() {
  cat <<EOF
Usage: $0 --start <pool> --end <pool> [options]

Required:
  --start <n>                  Start pool number
  --end <n>                    End pool number

Options:
  --host-octet <n>             Backend host octet (default: 20)
  --network-prefix <x.y>       Network prefix (default: 10.14)

  --http-output-dir <path>     HTTP config output dir
                               (default: /etc/nginx/sites-available)
  --stream-output-dir <path>   Stream snippet output dir
                               (default: /etc/nginx/streams-available)

  --overwrite                  Overwrite existing files
  --dry-run                    Print what would be done (no changes)
  -h, --help                   Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --start) START_POOL="$2"; shift 2 ;;
    --end) END_POOL="$2"; shift 2 ;;
    --host-octet) HOST_OCTET="$2"; shift 2 ;;
    --network-prefix) NETWORK_PREFIX="$2"; shift 2 ;;
    --http-output-dir) HTTP_OUTPUT_DIR="$2"; shift 2 ;;
    --stream-output-dir) STREAM_OUTPUT_DIR="$2"; shift 2 ;;
    --overwrite) OVERWRITE=true; shift ;;
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
  mkdir -p "$HTTP_OUTPUT_DIR"
  mkdir -p "$STREAM_OUTPUT_DIR"
fi

for pool in $(seq "$START_POOL" "$END_POOL"); do
  domain="${pool}.bleikervgs.no"
  backend_ip="${NETWORK_PREFIX}.${pool}.${HOST_OCTET}"

  http_filename="${domain}"
  http_filepath="${HTTP_OUTPUT_DIR}/${http_filename}"

  stream_filename="${domain}.stream.conf"
  stream_filepath="${STREAM_OUTPUT_DIR}/${stream_filename}"

  if [[ "$OVERWRITE" != true ]]; then
    if [[ -e "$http_filepath" ]]; then
      echo "Skipping existing HTTP file: $http_filepath"
    fi
    if [[ -e "$stream_filepath" ]]; then
      echo "Skipping existing stream file: $stream_filepath"
    fi
    if [[ -e "$http_filepath" || -e "$stream_filepath" ]]; then
      continue
    fi
  fi

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

  stream_config=$(cat <<EOF
# ${domain}
${domain} ${backend_ip}:443;
*.${domain} ${backend_ip}:443;
EOF
)

  if [[ "$DRY_RUN" == true ]]; then
    echo "----- HTTP: ${http_filepath} -----"
    echo "$http_config"
    echo
    echo "----- STREAM MAP ENTRY: ${stream_filepath} -----"
    echo "$stream_config"
    echo
  else
    echo "$http_config" > "$http_filepath"
    echo "Wrote HTTP config: $http_filepath"

    echo "$stream_config" > "$stream_filepath"
    echo "Wrote stream map entry: $stream_filepath"
  fi
done

echo
if [[ "$DRY_RUN" == true ]]; then
  echo "Dry run complete. No changes made."
else
  echo "Done."
  echo "Remember:"
  echo "  1. HTTP configs are in:        $HTTP_OUTPUT_DIR"
  echo "  2. Stream map entries are in:  $STREAM_OUTPUT_DIR"
  echo "  3. Enable configs separately with proxy-pool-enable.sh"
  echo "  4. Test nginx before reload:"
  echo "     sudo nginx -t && sudo systemctl reload nginx"
fi