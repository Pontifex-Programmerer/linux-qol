#!/usr/bin/env bash
set -euo pipefail

# change-ip.sh - set a static IP on Ubuntu netplan with fixed DNS and gateway pattern.
# Usage: sudo ./change-ip.sh [netplan-file]
# Default netplan-file: /etc/netplan/01-netcfg.yaml

NETPLAN_FILE='' # auto-select below if empty
IFACE_ARG=''
ADDRESS_ARG=''
GATEWAY_ARG=''
DNS_ARG=''
DRY_RUN=false
REVERT=false
HISTORY_DIR='/etc/netplan/history'

usage() {
  cat <<EOF
Usage: sudo ./change-ip.sh [options]

Options:
  --iface <name>           Force netplan interface name (e.g. eth0)
  --address <IP/CIDR>      Set static address directly (e.g. 10.10.1.42/24)
  --gateway <IP>           Set gateway directly (default .1 in subnet)
  --dns <ip,ip,...>       Set nameserver addresses (default 10.10.1.30)
  --netplan-file <path>    Use custom netplan file path (default: /etc/netplan/01-netcfg.yaml)
  --revert                 Revert to latest backup from history and apply
  --dry-run                Show generated netplan and do not apply changes
  --help                   Show this help message
EOF
  exit 0
}

error() { echo "ERROR: $1" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --iface)
      IFACE_ARG="$2"
      shift 2
      ;;
    --iface=*)
      IFACE_ARG="${1#*=}"
      shift
      ;;
    --address)
      ADDRESS_ARG="$2"
      shift 2
      ;;
    --address=*)
      ADDRESS_ARG="${1#*=}"
      shift
      ;;
    --gateway)
      GATEWAY_ARG="$2"
      shift 2
      ;;
    --gateway=*)
      GATEWAY_ARG="${1#*=}"
      shift
      ;;
    --dns)
      DNS_ARG="$2"
      shift 2
      ;;
    --dns=*)
      DNS_ARG="${1#*=}"
      shift
      ;;
    --netplan-file)
      NETPLAN_FILE="$2"
      shift 2
      ;;
    --netplan-file=*)
      NETPLAN_FILE="${1#*=}"
      shift
      ;;
    --revert)
      REVERT=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -h|--help)
      usage
      ;;
    *)
      error "Unknown argument: $1"
      ;;
  esac
done

if [[ $EUID -ne 0 ]]; then
  error "This script must be run as root (sudo)."
fi

mkdir -p "$HISTORY_DIR"

# Revert mode
if [[ "$REVERT" == true ]]; then
  if [[ -z "$NETPLAN_FILE" ]]; then
    files=(/etc/netplan/*.yaml)
    if [[ ${#files[@]} -eq 0 || ! -e ${files[0]} ]]; then
      error "No netplan file found to revert. Use --netplan-file."
    fi
    NETPLAN_FILE="${files[0]}"
  fi
  if [[ ! -f "$NETPLAN_FILE" ]]; then
    error "Netplan file $NETPLAN_FILE does not exist."
  fi

  base=$(basename "$NETPLAN_FILE" .yaml)
  latest=$(ls -1 "$HISTORY_DIR/${base}".bak.* 2>/dev/null | sort -V | tail -n 1 || true)
  if [[ -z "$latest" ]]; then
    error "No backups found in $HISTORY_DIR for $base."
  fi
  echo "Restoring $latest to $NETPLAN_FILE"
  cp -p "$latest" "$NETPLAN_FILE"
  rm -f "$latest"
  chmod 600 "$NETPLAN_FILE"
  echo "Applying restored netplan..."
  rm -f /run/netplan/netplan-try.ready 2>/dev/null || true
  netplan apply
  echo "Revert complete."
  exit 0
fi

# Auto-detect interface name (ignore lo and container/virtual interfaces)
IFACE=$(ip -o link show up | awk -F': ' '{print $2}' | grep -Ev '^(lo|vir|docker|veth|br|wl|tun|tap)' | head -n1 || true)
if [[ -z "$IFACE" ]]; then
  IFACE=$(ip -o link show | awk -F': ' '{print $2}' | grep -Ev '^(lo|vir|docker|veth|br|wl|tun|tap)' | head -n1 || true)
fi
if [[ -n "$IFACE_ARG" ]]; then
  IFACE="$IFACE_ARG"
fi

if [[ -z "$IFACE" ]]; then
  read -rp "Could not auto-detect interface. Enter interface name: " IFACE
  if [[ -z "$IFACE" ]]; then
    error "No interface provided."
  fi
fi

if [[ -n "$ADDRESS_ARG" ]]; then
  CIDR="$ADDRESS_ARG"
else
  read -rp "Enter new IP in CIDR form (e.g. 10.10.1.42/24): " CIDR
fi

if [[ -z "$CIDR" ]]; then
  error "No CIDR entered."
fi

if ! [[ "$CIDR" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/([0-9]|[1-2][0-9]|3[0-2])$ ]]; then
  error "Invalid CIDR format. Expected IPv4 CIDR like 10.10.1.42/24."
fi

IP=${CIDR%%/*}
PREFIX=${CIDR##*/}

# Validate each octet 0-255
IFS='.' read -r -a OCTETS <<< "$IP"
if [[ ${#OCTETS[@]} -ne 4 ]]; then
  error "Invalid IPv4 address."
fi
for octet in "${OCTETS[@]}"; do
  if ((octet < 0 || octet > 255)); then
    error "Invalid IPv4 octet: $octet."
  fi
done

if [[ -n "$GATEWAY_ARG" ]]; then
  GATEWAY="$GATEWAY_ARG"
else
  if [[ "$IP" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.[0-9]{1,3}$ ]]; then
    GATEWAY="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.${BASH_REMATCH[3]}.1"
  else
    error "Failed to compute gateway from IP. Provide --gateway explicitly."
  fi
fi

if [[ -n "$DNS_ARG" ]]; then
  DNS="$DNS_ARG"
else
  DNS="10.10.1.30"
fi

# select netplan file if not provided
if [[ -z "$NETPLAN_FILE" ]]; then
  files=(/etc/netplan/*.yaml)
  if [[ ${#files[@]} -eq 0 || ! -e ${files[0]} ]]; then
    NETPLAN_FILE='/etc/netplan/01-netcfg.yaml'
  else
    NETPLAN_FILE="${files[0]}"
  fi
fi

if [[ -e "$NETPLAN_FILE" && ! -w "$NETPLAN_FILE" ]]; then
  error "Netplan file $NETPLAN_FILE is not writable."
fi

if ! [[ "$GATEWAY" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
  error "Invalid gateway IP: $GATEWAY"
fi

IFS=',' read -r -a DNS_LIST <<< "$DNS"
DNS_CLEAN=()
for d in "${DNS_LIST[@]}"; do
  d=${d//[[:space:]]/}
  if [[ -n "$d" ]]; then
    if ! [[ "$d" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
      error "Invalid DNS IP: $d"
    fi
    DNS_CLEAN+=("$d")
  fi
done
if [[ ${#DNS_CLEAN[@]} -eq 0 ]]; then
  error "DNS list empty. Provide --dns or use default."
fi
DNS=$(IFS=,; echo "${DNS_CLEAN[*]}")
DNS_YAML="[$(IFS=,; echo "${DNS_CLEAN[*]}")]"

echo "Using new static IP: $IP/$PREFIX"
echo "Gateway: $GATEWAY"
echo "DNS: $DNS"

# backup previous config to history directory with incremental number
base=$(basename "$NETPLAN_FILE" .yaml)
mkdir -p "$HISTORY_DIR"
if [[ -f "$NETPLAN_FILE" ]]; then
  # find latest numeric suffix
  latest_num=0
  for old in "$HISTORY_DIR/${base}.bak."*; do
    if [[ -f "$old" ]]; then
      num=${old##*.bak.}
      if [[ "$num" =~ ^[0-9]+$ ]] && (( num > latest_num )); then
        latest_num=$num
      fi
    fi
  done
  next=$((latest_num + 1))
  backup="$HISTORY_DIR/${base}.bak.$next"
  echo "Backing up existing netplan config to $backup"
  cp -p "$NETPLAN_FILE" "$backup"
  saved_backup="$backup"
else
  saved_backup="none"
fi

# Warn if other netplan files exist to avoid duplicate default routes.
other_count=0
other_files=""
for f in /etc/netplan/*.yaml; do
  if [[ "$f" != "$NETPLAN_FILE" ]]; then
    other_count=$((other_count+1))
    other_files+="$f "
  fi
done
if [[ $other_count -gt 0 ]]; then
  echo "WARNING: found other netplan files: $other_files"
  echo "These may cause conflicting default routes. Remove/disable extras if needed."
fi

cat > "$NETPLAN_FILE" <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    $IFACE:
      dhcp4: false
      addresses: [${IP}/${PREFIX}]
      routes:
        - to: default
          via: ${GATEWAY}
      nameservers:
        addresses: ${DNS_YAML}
EOF
chmod 600 "$NETPLAN_FILE"
echo "Netplan config written to $NETPLAN_FILE"

if [[ "$DRY_RUN" == true ]]; then
  echo "Dry run enabled; not applying netplan. Preview of $NETPLAN_FILE:"
  echo "------"
  cat "$NETPLAN_FILE"
  echo "------"
  echo "Dry run complete."
  exit 0
fi

echo "Applying netplan (safe test mode)..."
rm -f /run/netplan/netplan-try.ready 2>/dev/null || true
if netplan try; then
  echo "netplan try succeeded. IP change confirmed."
  echo "Netplan changes are now applied."
else
  echo "netplan try failed or timed out. Attempting netplan apply anyway..."
  netplan apply
fi

if [[ -n "${SSH_CONNECTION:-}" ]]; then
  SSH_PEER=$(echo "$SSH_CONNECTION" | awk '{print $3}')
  echo "Checking connectivity to SSH peer $SSH_PEER..."
  if ping -c 2 "$SSH_PEER" >/dev/null 2>&1; then
    echo "SSH peer is reachable from this host. Remote session should be stable."
  else
    echo "Warning: SSH peer is not reachable from server. Keep console open and verify network before closing."
  fi
fi

cat <<EOF
✅ IP update complete.
- IP: ${IP}/${PREFIX}
- Gateway: ${GATEWAY}
- DNS: ${DNS}
- Netplan file: ${NETPLAN_FILE}
- Backup created: ${backup:-not created}

If this is a remote server, keep your SSH shell open and verify connectivity.
To rollback, restore the backup and run netplan apply.
EOF
