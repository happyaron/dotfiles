#!/bin/sh
# link-mon.sh — WAN link failover monitor.
#
# Probes two gateways, selects the best one based on availability and RTT,
# and calls set-routes.sh to apply routing changes.  Persists state across
# invocations via /var/lib/link-mon/link-mon.state.
#
# Intended to run from systemd timer about every 5 minutes.
#
# Dependencies: linkmon_lib.py (state/probe/validate), jq >= 1.6
# ---------------------------------------------------------------------------

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export LC_ALL=C
set -u

CONF_FILE="$(dirname "$0")/network.conf"
if [ ! -f "$CONF_FILE" ]; then
    echo "ERROR: $CONF_FILE not found. Copy network.conf.template and fill in values." >&2
    exit 1
fi
. "$CONF_FILE"

# ---- Paths ----------------------------------------------------------------

EXEC_SWITCH_CMD=/root/scripts/set-routes.sh
EXEC_STATE_DATA=/var/lib/link-mon/link-mon.state
LOCK_FILE=/var/lock/link-mon.lock
LINKMON_LIB="$(dirname "$0")/linkmon_lib.py"

# ---- Tuning ---------------------------------------------------------------

HYSTERESIS_MS=40
COOLDOWN_SECONDS=600
PING_COUNT=3
PING_DEADLINE=5
TEST_TARGET=8.8.4.4

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

log() { printf '%s\n' "$*"; }

# FD 9 (the flock) is inherited by the child so set-routes.sh can verify
# the lock via /proc/self/fd/9 and skip re-acquisition.
run_switch_cmd() {
	"$EXEC_SWITCH_CMD" "$@"
}

verify_routes_intact() {
	if ! ip link show dev "$LINKDEV_ACTIVE" up >/dev/null 2>&1; then
		log "verify: $LINKDEV_ACTIVE is not up"
		return 1
	fi

	if ! ip route show default | grep -qF "via $LINKGW_ACTIVE dev $LINKDEV_ACTIVE"; then
		log "verify: default route via $LINKGW_ACTIVE dev $LINKDEV_ACTIVE missing"
		return 1
	fi

	if [ "$LINKDEV_ACTIVE" = "$LINKDEV_0" ]; then
		if ! ip route show | grep -qF "${LINKGW_0} dev ${LINKDEV_0}"; then
			log "verify: ${LINKDEV_0} host route missing"
			return 1
		fi
	fi

	return 0
}

write_state() {
	python3 "$LINKMON_LIB" state write "$EXEC_STATE_DATA" \
		--routing-mode "$ROUTING_MODE" \
		--active-gw "$LINKGW_ACTIVE" --active-dev "$LINKDEV_ACTIVE" \
		--active-rtt "${LINKRTT_ACTIVE:-}" \
		--backup-gw "${LINKGW_BACKUP:-}" --backup-dev "${LINKDEV_BACKUP:-}" \
		--backup-rtt "${LINKRTT_BACKUP:-}" \
		--stamp-time "$STAMP_TIME" \
		--check "$1"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

# ---- Lock acquisition -----------------------------------------------------

mkdir -p "$(dirname "$LOCK_FILE")"
touch "$LOCK_FILE"
chmod 600 "$LOCK_FILE"
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
	log "Another instance is running, exit." >&2
	exit 0
fi
export LINK_MON_LOCKED=1

linkmon_cleanup() {
	_child=${!:-}
	if [ -n "$_child" ] && kill -0 "$_child" 2>/dev/null; then
		kill -TERM "$_child" 2>/dev/null || true
		wait "$_child" 2>/dev/null || true
	fi
	exec 9>&- 2>/dev/null || true
}
trap linkmon_cleanup EXIT INT TERM
trap 'exit 1' INT TERM

mkdir -p "$(dirname "$EXEC_STATE_DATA")"

# ---- Dependency checks ----------------------------------------------------

if ! [ -x "$EXEC_SWITCH_CMD" ]; then
	log "EXEC_SWITCH_CMD not found: $EXEC_SWITCH_CMD" >&2
	exit 1
fi

for _dep in python3 jq; do
	if ! command -v "$_dep" >/dev/null 2>&1; then
		log "ERROR: required dependency not found: $_dep" >&2
		exit 1
	fi
done

if ! [ -f "$LINKMON_LIB" ]; then
	log "ERROR: linkmon_lib.py not found: $LINKMON_LIB" >&2
	exit 1
fi

# ---- Load state -----------------------------------------------------------

_state_json=$(python3 "$LINKMON_LIB" state read "$EXEC_STATE_DATA")

STAMP_TIME=$(printf '%s' "$_state_json" | jq -r '.stamp_time // "0"')
ROUTING_MODE=$(printf '%s' "$_state_json" | jq -r '.routing_mode // ""')

LINKGW_ACTIVE=$(printf '%s' "$_state_json" | jq -r '.active_gw // ""')
LINKDEV_ACTIVE=$(printf '%s' "$_state_json" | jq -r '.active_dev // ""')
LINKRTT_ACTIVE=$(printf '%s' "$_state_json" | jq -r '.active_rtt // ""')

LINKGW_BACKUP=$(printf '%s' "$_state_json" | jq -r '.backup_gw // ""')
LINKDEV_BACKUP=$(printf '%s' "$_state_json" | jq -r '.backup_dev // ""')
LINKRTT_BACKUP=$(printf '%s' "$_state_json" | jq -r '.backup_rtt // ""')

_prev_active_gw="$LINKGW_ACTIVE"
_prev_active_dev="$LINKDEV_ACTIVE"

# ---- Probe ----------------------------------------------------------------

if [ "$LINKGW_ACTIVE" = "$LINKGW_1" ] && [ "$LINKDEV_ACTIVE" = "$LINKDEV_1" ]; then
	PROBEGW_NOW="$LINKGW_1"
	PROBEDEV_NOW="$LINKDEV_1"
	PROBEGW_BAK="$LINKGW_0"
	PROBEDEV_BAK="$LINKDEV_0"
else
	PROBEGW_NOW="$LINKGW_0"
	PROBEDEV_NOW="$LINKDEV_0"
	PROBEGW_BAK="$LINKGW_1"
	PROBEDEV_BAK="$LINKDEV_1"
fi

_probe_json=$(python3 "$LINKMON_LIB" probe \
	--incumbent-gw "$PROBEGW_NOW" --incumbent-dev "$PROBEDEV_NOW" \
	--challenger-gw "$PROBEGW_BAK" --challenger-dev "$PROBEDEV_BAK" \
	--hysteresis "$HYSTERESIS_MS" --cooldown "$COOLDOWN_SECONDS" \
	--last-switch "${STAMP_TIME:-0}" \
	--count "$PING_COUNT" --deadline "$PING_DEADLINE")

PROBE_ALIVE=$(printf '%s' "$_probe_json" | jq -r '.alive')

if [ "$PROBE_ALIVE" -ne 2 ]; then
	LINKGW_ACTIVE=$(printf '%s' "$_probe_json" | jq -r '.active_gw')
	LINKDEV_ACTIVE=$(printf '%s' "$_probe_json" | jq -r '.active_dev')
	LINKRTT_ACTIVE=$(printf '%s' "$_probe_json" | jq -r '.active_rtt')
	LINKGW_BACKUP=$(printf '%s' "$_probe_json" | jq -r '.backup_gw')
	LINKDEV_BACKUP=$(printf '%s' "$_probe_json" | jq -r '.backup_dev')
	LINKRTT_BACKUP=$(printf '%s' "$_probe_json" | jq -r '.backup_rtt')
fi

# ---- Act on probe result -------------------------------------------------

if [ "$PROBE_ALIVE" -eq 2 ]; then
	if [ -n "$LINKGW_ACTIVE" ] && [ -n "$LINKDEV_ACTIVE" ]; then
		ROUTING_MODE=LOCAL
		run_switch_cmd --fast "$LINKGW_ACTIVE" "$LINKDEV_ACTIVE" \
			"${LINKGW_BACKUP:-}" "${LINKDEV_BACKUP:-}" "$ROUTING_MODE"
		_rc=$?
		if [ "$_rc" -ne 0 ]; then
			log "ERROR: set-routes.sh failed (exit $_rc)" >&2
			ROUTING_MODE=FAILED
		fi
	else
		ROUTING_MODE=LOCAL
		run_switch_cmd restore || true
	fi
elif [ "$ROUTING_MODE" != "NORMAL" ] || [ "$PROBE_ALIVE" -eq 1 ]; then
	ROUTING_MODE=NORMAL
	run_switch_cmd --fast "$LINKGW_ACTIVE" "$LINKDEV_ACTIVE" \
		"$LINKGW_BACKUP" "$LINKDEV_BACKUP" "$ROUTING_MODE"
	_rc=$?
	if [ "$_rc" -ne 0 ]; then
		log "ERROR: set-routes.sh failed (exit $_rc)" >&2
		ROUTING_MODE=FAILED
	fi
	# Only reset cooldown stamp when the active link actually changed.
	if [ "$PROBE_ALIVE" -eq 1 ] \
	   && { [ "$_prev_active_gw" != "$LINKGW_ACTIVE" ] \
	        || [ "$_prev_active_dev" != "$LINKDEV_ACTIVE" ]; }; then
		_stamp_needed=1
	fi
else
	if verify_routes_intact; then
		ROUTING_MODE=NORMAL
	else
		log "Route drift detected, re-applying."
		ROUTING_MODE=NORMAL
		run_switch_cmd --fast "$LINKGW_ACTIVE" "$LINKDEV_ACTIVE" \
			"$LINKGW_BACKUP" "$LINKDEV_BACKUP" "$ROUTING_MODE"
		_rc=$?
		if [ "$_rc" -ne 0 ]; then
			log "ERROR: set-routes.sh failed (exit $_rc)" >&2
			ROUTING_MODE=FAILED
		fi
	fi
fi

# ---- Persist state --------------------------------------------------------

if [ "${_stamp_needed:-0}" = "1" ]; then
	STAMP_TIME=$(date +%s)
fi

write_state PENDING || log "WARNING: failed to persist state" >&2

if verify_routes_intact \
   && ping -q -c 1 -w "$PING_DEADLINE" "$TEST_TARGET" >/dev/null 2>&1; then
	write_state PASS || true
else
	write_state FAIL || true
fi
