#!/bin/bash
# Remove r730-fan-control and hand fan control back to the iDRAC. Run as root.
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "run as root" >&2
    exit 1
fi

systemctl disable --now r730-fan-control.timer || true
systemctl start r730-fan-auto.service   # never leave the fans stranded in manual mode

rm -f /usr/local/bin/r730-fan-control.sh \
      /etc/systemd/system/r730-fan-control.service \
      /etc/systemd/system/r730-fan-control.timer \
      /etc/systemd/system/r730-fan-auto.service
systemctl daemon-reload

echo "removed — fans are back under iDRAC automatic control"
if [ -e /etc/default/r730-fan-control ]; then
    echo "kept /etc/default/r730-fan-control (your tuning) — delete it manually if unwanted"
fi
