#!/bin/bash
# Schedule-based manual fan control for a Dell R730, with a temperature
# failsafe that hands control back to the iDRAC when the server runs hot.
# Runs on the R730 itself via the kernel IPMI interface (/dev/ipmi0).
set -u

TAG="r730-fan-control"

# Overrides live in /etc/default/r730-fan-control; every knob below falls back
# to its built-in default when unset there.
CONFIG="${R730_FAN_CONFIG:-/etc/default/r730-fan-control}"
if [ -r "$CONFIG" ]; then
    # shellcheck source=/dev/null
    . "$CONFIG"
fi

IPMITOOL="${IPMITOOL:-/usr/bin/ipmitool}"

# --- Schedule ---------------------------------------------------------------
DAY_START="${DAY_START:-8}"                 # day begins 08:00
DAY_END="${DAY_END:-20}"                    # day ends 19:59
WINTER_MONTHS="${WINTER_MONTHS:-12 1 2}"    # Dec, Jan, Feb

# --- Fan speeds (hex percent) -----------------------------------------------
WINTER_DAY="${WINTER_DAY:-0x19}"      # 25%
WINTER_NIGHT="${WINTER_NIGHT:-0x14}"  # 20%
SUMMER_DAY="${SUMMER_DAY:-0x26}"      # 38%
SUMMER_NIGHT="${SUMMER_NIGHT:-0x1e}"  # 30%

# --- Failsafe thresholds (degrees C) ----------------------------------------
# At/above either MAX: revert to iDRAC automatic control.
# At/below both RESUME: safe to (re)apply manual control.
# In between: leave whatever mode is active alone (hysteresis, no flapping).
EXHAUST_MAX="${EXHAUST_MAX:-45}"
CPU_MAX="${CPU_MAX:-75}"
EXHAUST_RESUME="${EXHAUST_RESUME:-40}"
CPU_RESUME="${CPU_RESUME:-68}"

# HOUR_OVERRIDE / MONTH_OVERRIDE exist for testing the schedule logic.
HOUR="${HOUR_OVERRIDE:-$(date +%-H)}"
MONTH="${MONTH_OVERRIDE:-$(date +%-m)}"

log() { logger -t "$TAG" -- "$*"; echo "$TAG: $*"; }

auto_mode()   { "$IPMITOOL" raw 0x30 0x30 0x01 0x01 >/dev/null; }
manual_mode() { "$IPMITOOL" raw 0x30 0x30 0x01 0x00 >/dev/null; }
set_speed()   { "$IPMITOOL" raw 0x30 0x30 0x02 0xff "$1" >/dev/null; }

# --- Read temperatures ------------------------------------------------------
SDR="$("$IPMITOOL" sdr type temperature 2>/dev/null)"

EXHAUST="$(awk -F'|' '$1 ~ /^Exhaust Temp/ && $5 ~ /degrees/ {
    gsub(/[^0-9]/, "", $5); print $5; exit }' <<<"$SDR")"

# CPU sensors report as bare "Temp" rows on the R730; take the hottest one.
CPU="$(awk -F'|' '$1 ~ /^Temp[[:space:]]/ && $5 ~ /degrees/ {
    gsub(/[^0-9]/, "", $5); if ($5 + 0 > max) max = $5 + 0 }
    END { if (max != "") print max }' <<<"$SDR")"

if [ -z "$EXHAUST" ] || [ -z "$CPU" ]; then
    log "temperature read failed (exhaust='${EXHAUST}' cpu='${CPU}') — reverting to iDRAC automatic fan control"
    auto_mode
    exit 1
fi

# --- Failsafe ---------------------------------------------------------------
if [ "$EXHAUST" -ge "$EXHAUST_MAX" ] || [ "$CPU" -ge "$CPU_MAX" ]; then
    if auto_mode; then
        log "HOT: exhaust ${EXHAUST}C cpu ${CPU}C — reverted to iDRAC automatic fan control"
        exit 0
    fi
    log "HOT: exhaust ${EXHAUST}C cpu ${CPU}C — FAILED to revert to automatic control"
    exit 1
fi

if [ "$EXHAUST" -gt "$EXHAUST_RESUME" ] || [ "$CPU" -gt "$CPU_RESUME" ]; then
    log "cooling down: exhaust ${EXHAUST}C cpu ${CPU}C — leaving current fan mode unchanged"
    exit 0
fi

# --- Pick scheduled speed ---------------------------------------------------
if [ "$HOUR" -ge "$DAY_START" ] && [ "$HOUR" -lt "$DAY_END" ]; then
    IS_DAY=true
else
    IS_DAY=false
fi

case " $WINTER_MONTHS " in
    *" $MONTH "*)
        if [ "$IS_DAY" = true ]; then HEX_SPEED=$WINTER_DAY; else HEX_SPEED=$WINTER_NIGHT; fi
        ;;
    *)
        if [ "$IS_DAY" = true ]; then HEX_SPEED=$SUMMER_DAY; else HEX_SPEED=$SUMMER_NIGHT; fi
        ;;
esac

if manual_mode && set_speed "$HEX_SPEED"; then
    log "manual fan speed set to $((HEX_SPEED))% ($HEX_SPEED) — exhaust ${EXHAUST}C, cpu ${CPU}C"
else
    log "failed to set manual fan speed — reverting to iDRAC automatic fan control"
    auto_mode
    exit 1
fi
