# r730-fan-control

Scheduled manual fan control for a Dell R730 with a temperature failsafe,
companion to [md1200-fan-control](https://github.com/uprightbass360/md1200-fan-control-systemd)
for the JBOD.

## What it does

Every 5 minutes a systemd timer runs `r730-fan-control.sh` on the R730:

1. Reads exhaust and CPU temperatures locally (`ipmitool sdr type temperature`).
2. **Failsafe:** exhaust ≥ 45°C or CPU ≥ 75°C → reverts to iDRAC automatic
   fan control. Between the max and resume thresholds (exhaust 40°C / CPU
   68°C) it leaves the current mode alone so it doesn't flap. A failed
   temperature read also reverts to automatic.
3. Otherwise enables manual mode and applies the scheduled speed
   (re-asserted every run, since an iDRAC reset silently reverts to auto):

   | | Day (08:00–19:59) | Night |
   |---|---|---|
   | Winter (Dec–Feb) | 25% | 20% |
   | Other months | 30% | 25% |

## Install

Copy this directory to the R730, then as root:

```sh
./install.sh
```

## Configure

Speeds, thresholds, and the day/winter schedule are set in
`/etc/default/r730-fan-control` (seeded from `r730-fan-control.env` on first
install, then left alone — your tuning survives re-installs and updates).
Uncomment a variable to override its built-in default; changes apply on the
next timer run, within 5 minutes. The run interval itself lives in the timer:
`systemctl edit r730-fan-control.timer`.

## Watch it

```sh
journalctl -u r730-fan-control -f
```

## Escape hatch

Give control back to the iDRAC at any time:

```sh
systemctl stop r730-fan-control.timer && systemctl start r730-fan-auto
```

`./uninstall.sh` removes everything and also restores automatic control.
