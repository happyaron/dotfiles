#!/bin/sh
# set -x
set -u
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export LC_ALL=C

CONF_FILE="$(dirname "$0")/network.conf"
if [ ! -f "$CONF_FILE" ]; then
    echo "ERROR: $CONF_FILE not found. Copy network.conf.template and fill in values." >&2
    exit 1
fi
. "$CONF_FILE"

LOCK_FILE=/var/lock/link-mon.lock
LINKMON_LIB="$(dirname "$0")/linkmon_lib.py"

# Verify lock is actually held - don't trust environment variable alone
_verify_lock=0
if [ "${LINK_MON_LOCKED:-0}" = "1" ]; then
    # Check if FD 9 is actually open (proves caller holds flock)
    if [ -e /proc/self/fd/9 ]; then
        _verify_lock=1
    fi
fi

if [ "$_verify_lock" != "1" ]; then
    exec 9>"$LOCK_FILE"
    if ! flock -n 9; then
        echo "Another routing operation in progress, exit." >&2
        exit 1
    fi
fi
unset _verify_lock

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

# Route priorities (metrics)
METRIC_WG=100
METRIC_DEFAULT=1000
METRIC_SECONDARY=2000

# IP list freshness (7 days)
STALE_SECONDS=$((7 * 86400))

# Working directories (hardcoded for security - was: override via environment)
DIR_WORK=/root/scripts
DIR_TXT=/root/routes
IPLIST_GEN="${DIR_WORK}/generate-ip-list.py"
readonly DIR_WORK DIR_TXT IPLIST_GEN

# Files produced by generate-ip-list.py that generate_ip_rules() consumes.
GENERATED_FILES="chn.txt google.txt"

# ---------------------------------------------------------------------------
# Route configuration -- loaded from network.conf
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

ROUTE_BACKUP=""

# ---------------------------------------------------------------------------
# Validation (delegated to linkmon_lib.py)
# ---------------------------------------------------------------------------

validate_ip() {
    if ! python3 "$LINKMON_LIB" validate ip "$1"; then
        echo "ERROR: Invalid IP address: $1" >&2
        return 1
    fi
}

validate_iface() {
    if ! python3 "$LINKMON_LIB" validate iface "$1"; then
        echo "ERROR: Invalid interface name: $1" >&2
        return 1
    fi
}

validate_cidr() {
    if ! python3 "$LINKMON_LIB" validate cidr "$1"; then
        echo "ERROR: Invalid CIDR format: $1" >&2
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Cleanup / traps
# ---------------------------------------------------------------------------

cleanup() {
    _cleanup_rc=$?
    exec 9>&- 2>/dev/null || true
    # Clean up temporary route batch file
    if [ -f "${DIR_TXT}/iproute.tmp" ]; then
        rm -f "${DIR_TXT}/iproute.tmp" 2>/dev/null || true
    fi
    if [ "$_cleanup_rc" -eq 0 ] && [ -n "${ROUTE_BACKUP:-}" ] && [ -f "${ROUTE_BACKUP}" ]; then
        rm -f "${ROUTE_BACKUP}" 2>/dev/null || true
    fi
    return 0
}
trap cleanup EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

is_iface_up() {
    ip link show dev "$1" up >/dev/null 2>&1
}

wait_for_iface() {
    _wfi_iface="$1"
    _wfi_max_attempts="${2:-3}"
    _wfi_delay="${3:-5}"
    _wfi_attempt=0

    while [ $_wfi_attempt -lt "$_wfi_max_attempts" ]; do
        if is_iface_up "$_wfi_iface"; then
            return 0
        fi
        _wfi_attempt=$((_wfi_attempt + 1))
        if [ $_wfi_attempt -lt "$_wfi_max_attempts" ]; then
            echo "Interface $_wfi_iface not up, waiting ${_wfi_delay}s (attempt $_wfi_attempt/$_wfi_max_attempts)..."
            sleep "$_wfi_delay"
        fi
    done
    return 1
}

ip_lists_are_fresh() {
    _ilf_now=$(date +%s)
    for _ilf_f in ${GENERATED_FILES}; do
        _ilf_path="${DIR_TXT}/${_ilf_f}"
        [ -s "$_ilf_path" ] || return 1
        _ilf_mtime=$(stat -c %Y "$_ilf_path" 2>/dev/null) || return 1
        _ilf_age=$((_ilf_now - _ilf_mtime))
        if [ "$_ilf_age" -gt "${STALE_SECONDS}" ]; then
            return 1
        fi
    done
    return 0
}

restore_default_route() {
    _rdr_rc=0
    ip ro flush scope global
    ip ro replace default via "${DEFAULTGW}" dev "${DEFAULTDEV}" src "${DEFAULTSRC}" metric "${METRIC_DEFAULT}" || {
        echo "ERROR: failed to set primary default route" >&2
        _rdr_rc=1
    }
    ip ro replace default via "${SECONDGW}" dev "${SECONDDEV}" src "${SECONDSRC}" metric "${METRIC_SECONDARY}" || {
        echo "ERROR: failed to set secondary default route" >&2
        _rdr_rc=1
    }
    # Ensure the kernel's connected route for SECONDNET is intact.
    # A previous flush or replace may have clobbered the scope-link route
    # that the kernel auto-creates when the address is assigned.
    # We must NOT "ip ro replace SECONDNET via GW" — that overwrites the
    # connected route and breaks direct L2 delivery to hosts on that subnet.
    if ! ip ro show "${SECONDNET}" dev "${SECONDDEV}" scope link 2>/dev/null | grep -q .; then
        ip ro add "${SECONDNET}" dev "${SECONDDEV}" scope link || {
            echo "ERROR: failed to restore connected route for ${SECONDNET}" >&2
            _rdr_rc=1
        }
    fi
    return $_rdr_rc
}

save_backup() {
    _sb_tmpfile=$(mktemp /tmp/route-backup.XXXXXX)
    if [ -z "$_sb_tmpfile" ] || [ ! -f "$_sb_tmpfile" ]; then
        echo "ERROR: Failed to create backup file" >&2
        return 1
    fi

    if ! ip route save table main > "$_sb_tmpfile" 2>/dev/null; then
        echo "ERROR: Failed to save current routes" >&2
        rm -f "$_sb_tmpfile"
        return 1
    fi

    _sb_route_count=$(wc -c < "$_sb_tmpfile")
    if [ "$_sb_route_count" -eq 0 ]; then
        echo "ERROR: Backup file is empty, routes not saved" >&2
        rm -f "$_sb_tmpfile"
        return 1
    fi

    ROUTE_BACKUP="$_sb_tmpfile"
    echo "Routes backed up to ${ROUTE_BACKUP} (${_sb_route_count} bytes)"
    return 0
}

rollback_from_backup() {
    if [ -n "${ROUTE_BACKUP}" ] && [ -f "${ROUTE_BACKUP}" ]; then
        echo "Restoring routes from backup."
        ip route flush scope global
        if ! ip route restore < "${ROUTE_BACKUP}"; then
            echo "ERROR: Failed to restore from backup, falling back to defaults" >&2
            restore_default_route
            return 1
        fi
    else
        echo "No backup available, restoring default routes."
        restore_default_route
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Subcommands
# ---------------------------------------------------------------------------

do_restore() {
    rollback_from_backup
}

do_apply() {
    _force_regen=no
    _allow_stale=no
    _local_only=no

    while true; do
        case "${1:-}" in
            --force)
                _force_regen=yes
                shift
                ;;
            --fast)
                _allow_stale=yes
                shift
                ;;
            *)
                break
                ;;
        esac
    done

    _routing_mode="${5:-}"

    if [ -n "${1:-}" ] && [ -n "${2:-}" ]; then
        if ! validate_ip "$1"; then
            echo "ERROR: Invalid ROUTEGW_0 IP address: $1" >&2
            exit 1
        fi
        if ! validate_iface "$2"; then
            echo "ERROR: Invalid ROUTEDEV_0 interface: $2" >&2
            exit 1
        fi
        ROUTEGW_0="$1"
        ROUTEDEV_0="$2"
    fi

    if [ -n "${3:-}" ] && [ -n "${4:-}" ]; then
        if ! validate_ip "$3"; then
            echo "ERROR: Invalid ROUTEGW_1 IP address: $3" >&2
            exit 1
        fi
        if ! validate_iface "$4"; then
            echo "ERROR: Invalid ROUTEDEV_1 interface: $4" >&2
            exit 1
        fi
        ROUTEGW_1="$3"
        ROUTEDEV_1="$4"
    fi

    if [ "$_routing_mode" = "LOCAL" ]; then
        _local_only=yes
    fi

    if ! wait_for_iface "${DEFAULTDEV}" 3 5; then
        echo "ERROR: Routing device ${DEFAULTDEV} is not up, network inaccessible, exit." >&2
        exit 1
    fi

    if ! save_backup; then
        echo "ERROR: Failed to save route backup, aborting." >&2
        exit 1
    fi

    if [ "$_local_only" = "yes" ]; then
        restore_default_route
        echo "Local routing requested, accept."
        exit 0
    elif ! is_iface_up "${ROUTEDEV_0}"; then
        restore_default_route
        echo "Routing device ${ROUTEDEV_0} is not up, local routing only."
        exit 0
    fi

    restore_default_route

    if [ ! -d "${DIR_TXT}" ]; then
        echo "ERROR: ${DIR_TXT} is not a directory, give up." >&2
        rollback_from_backup
        exit 1
    fi

    if [ ! -f "$IPLIST_GEN" ]; then
        echo "ERROR: IP list generator not found: $IPLIST_GEN" >&2
        rollback_from_backup
        exit 1
    fi

    if [ ! -x "$IPLIST_GEN" ]; then
        echo "ERROR: IP list generator not executable: $IPLIST_GEN" >&2
        rollback_from_backup
        exit 1
    fi

    set -- -o "${DIR_TXT}"
    set -- "$@" --gen-routes "${DIR_TXT}/iproute.tmp"
    
    set -- "$@" --route-gw0 "${ROUTEGW_0}" --route-dev0 "${ROUTEDEV_0}"
    set -- "$@" --route-gw1 "${ROUTEGW_1}" --route-dev1 "${ROUTEDEV_1}"
    
    set -- "$@" --default-gw "${DEFAULTGW}" --default-dev "${DEFAULTDEV}" --default-src "${DEFAULTSRC}"
    set -- "$@" --second-gw "${SECONDGW}" --second-dev "${SECONDDEV}" --second-src "${SECONDSRC}"

    if is_iface_up "${ROUTEDEV_0}"; then
        set -- "$@" --route-peer0 "${ROUTEPEER_0}"
    fi

    set -- "$@" --metric-wg "${METRIC_WG}" --metric-default "${METRIC_DEFAULT}" --metric-second "${METRIC_SECONDARY}"

    if [ "$_force_regen" = "yes" ] || { [ "$_allow_stale" != "yes" ] && ! ip_lists_are_fresh; }; then
        echo "Generating IP lists..."
        set -- "$@" --skip-ipv6 --skip-oci --skip-aws --skip-gcp
    else
        echo "IP lists are fresh, skipping regeneration."
        set -- "$@" --skip-cn --skip-google --skip-gcp --skip-aws --skip-oci
    fi

    if ! python3 "$IPLIST_GEN" "$@"; then
        echo "ERROR: IP list generation failed" >&2
        rollback_from_backup
        exit 1
    fi

    if [ ! -s "${DIR_TXT}/iproute.tmp" ]; then
        echo "ERROR: ${DIR_TXT}/iproute.tmp is missing or empty after generation." >&2
        rollback_from_backup
        exit 1
    fi

    if ! ip -batch "${DIR_TXT}/iproute.tmp"; then
        echo "ERROR: ip batch apply failed, rolling back..." >&2
        echo "  Check interface status: ip link show ${ROUTEDEV_0} ${ROUTEDEV_1} ${SECONDDEV}" >&2
        rollback_from_backup
        exit 1
    fi

    if [ -x "${DIR_WORK}/set-pbr.sh" ]; then
        _pbr_rc=0
        sh "${DIR_WORK}/set-pbr.sh" || _pbr_rc=$?
        if [ "$_pbr_rc" -ne 0 ]; then
            echo "WARNING: set-pbr.sh failed (exit $_pbr_rc ), continuing."
        fi
    fi

    rndc flush 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

case "${1:-}" in
    restore)
        do_restore
        ;;
    *)
        do_apply "$@"
        ;;
esac
