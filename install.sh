#!/bin/bash
# Install r730-fan-control on the R730. Run as root on the server.
set -euo pipefail

cd "$(dirname "$0")"

if [ "$(id -u)" -ne 0 ]; then
    echo "run as root" >&2
    exit 1
fi

if ! command -v ipmitool >/dev/null; then
    echo "ipmitool not found — install it first (apt install ipmitool)" >&2
    exit 1
fi

# Local IPMI needs the kernel interface; load it now and on every boot.
if [ ! -e /dev/ipmi0 ]; then
    modprobe ipmi_si ipmi_devintf
    printf 'ipmi_si\nipmi_devintf\n' > /etc/modules-load.d/ipmi.conf
fi

install -m 755 r730-fan-control.sh /usr/local/bin/r730-fan-control.sh
install -m 644 r730-fan-control.service r730-fan-control.timer r730-fan-auto.service \
    /etc/systemd/system/

# Seed the config file only if absent, so tuning survives re-installs.
if [ ! -e /etc/default/r730-fan-control ]; then
    install -m 644 r730-fan-control.env /etc/default/r730-fan-control
fi

systemctl daemon-reload
systemctl enable --now r730-fan-control.timer
systemctl start r730-fan-control.service

echo
systemctl status --no-pager r730-fan-control.timer | head -5
journalctl -u r730-fan-control.service --no-pager -n 3
