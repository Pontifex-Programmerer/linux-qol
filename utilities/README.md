# Linux QoL Scripts

This repository contains Ubuntu quality-of-life scripts. The first script is `change-ip.sh`, which updates a netplan config to set a static IP and applies it.

## Script: `change-ip.sh`

### Behavior
- Prompts for a new IP in CIDR format (e.g. `10.10.1.42/24`).
- Gateway is derived from the same subnet with `.1` as the host (e.g. `10.10.1.1`).
- DNS is always set to `10.10.1.30`.
- Auto-detects network interface; can also force interface via `--iface`.
- Backs up existing netplan file before overwriting.

### Usage

```bash
sudo ./change-ip.sh
```

Optional arguments:

```bash
sudo ./change-ip.sh --iface eth0
sudo ./change-ip.sh --address 10.10.1.42/24
sudo ./change-ip.sh --gateway 10.10.1.1
sudo ./change-ip.sh --dns 10.10.1.30,8.8.8.8
sudo ./change-ip.sh --netplan-file /etc/netplan/50-cloud-init.yaml
sudo ./change-ip.sh --revert
sudo ./change-ip.sh --dry-run
```

### Example

```bash
sudo ./change-ip.sh
Enter new IP in CIDR form (e.g. 10.10.1.42/24): 10.10.1.55/24
```

### Important

- Run this on your Ubuntu server.
- Keep an SSH session open while applying changes so you can recover if network breaks.
- The script uses `netplan try` for safer apply and then `netplan apply`.

### Quick verify before/after

```bash
sudo cat /etc/netplan/*.yaml
sudo ./change-ip.sh --dry-run --address 10.10.1.42/24 --dns 10.10.1.30,8.8.8.8
sudo ./change-ip.sh --address 10.10.1.42/24 --dns 10.10.1.30,8.8.8.8
sudo cat /etc/netplan/*.yaml
```

If you need to rollback:

```bash
sudo cp /etc/netplan/01-netcfg.yaml.bak.<TIMESTAMP> /etc/netplan/01-netcfg.yaml
sudo netplan apply
```

## Notes

- This is for predictable environments where gateway is always `.1`.
- Use a valid IPv4 CIDR input.

### Quick alias for frequent use

Add this to your shell profile:

```bash
alias changeip='sudo ~/dev/linux-qol-scripts/change-ip.sh --dry-run'
```

Then run:

```bash
changeip --address 10.10.1.55/24 --dns 10.10.1.30,8.8.8.8
```

