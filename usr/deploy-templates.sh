#!/bin/sh
# deploy-templates.sh — Substitute <VARNAME> placeholders in config files
# that cannot source network.conf directly (systemd units, ipsec-tools.conf).
#
# Reads values from network.conf, replaces every <VARNAME> occurrence in the
# target files with the corresponding value, and writes the result.
#
# Usage:
#   deploy-templates.sh                     # dry-run (show diffs)
#   deploy-templates.sh --apply             # substitute in place
#   deploy-templates.sh --install PREFIX    # write substituted files under PREFIX
#
set -eu
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONF_FILE="${SCRIPT_DIR}/network-scripts/network.conf"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [ ! -f "$CONF_FILE" ]; then
    echo "ERROR: $CONF_FILE not found." >&2
    echo "Copy network.conf.template to network.conf and fill in values." >&2
    exit 1
fi

TEMPLATE_FILES="
systemd/system/link-mon.service
systemd/system/split-access.service
systemd/system/tunnel-boot.service
usr/ipsec-tools.conf
"

MODE=dryrun
INSTALL_PREFIX=""
case "${1:-}" in
    --apply)  MODE=apply ;;
    --install)
        MODE=install
        INSTALL_PREFIX="${2:?'--install requires a PREFIX argument (e.g. / or /etc)'}"
        ;;
    --help|-h)
        echo "Usage: $0 [--apply | --install PREFIX]"
        echo "  (no args)        dry-run: show diffs"
        echo "  --apply          substitute in place (repo working copy)"
        echo "  --install PREFIX copy substituted files under PREFIX"
        exit 0
        ;;
    "")       MODE=dryrun ;;
    *)        echo "Unknown option: $1" >&2; exit 1 ;;
esac

# --- Build a sed script from placeholders found in template files -----------

_sed_file="${TMPDIR:-/tmp}/deploy-templates.$$.sed"
trap 'rm -f "$_sed_file"' EXIT

: > "$_sed_file"

# Collect all unique <PLACEHOLDER> names across template files
_all_vars=""
for _rel in $TEMPLATE_FILES; do
    _src="${REPO_ROOT}/${_rel}"
    [ -f "$_src" ] || continue
    _found=$(grep -oE '<[A-Z_0-9]+>' "$_src" | sed 's/^<//;s/>$//' | sort -u)
    for _v in $_found; do
        case " $_all_vars " in
            *" $_v "*) ;;
            *) _all_vars="$_all_vars $_v" ;;
        esac
    done
done

if [ -z "$_all_vars" ]; then
    echo "No placeholders to substitute."
    exit 0
fi

# Source config and resolve each variable
(
    . "$CONF_FILE"
    for _v in $_all_vars; do
        eval "_val=\${${_v}:-}"
        if [ -n "$_val" ]; then
            _val_esc=$(printf '%s' "$_val" | sed 's/[\\&/]/\\&/g')
            printf 's/<%s>/%s/g\n' "$_v" "$_val_esc"
        else
            echo "WARNING: variable $_v has no value in network.conf" >&2
        fi
    done
) > "$_sed_file"

if [ ! -s "$_sed_file" ]; then
    echo "ERROR: failed to generate substitution rules." >&2
    exit 1
fi

# --- Apply substitutions ----------------------------------------------------

_rc=0
for _rel in $TEMPLATE_FILES; do
    _src="${REPO_ROOT}/${_rel}"
    [ -f "$_src" ] || continue
    grep -qE '<[A-Z_0-9]+>' "$_src" || continue

    _result=$(sed -f "$_sed_file" "$_src")

    _unresolved=$(printf '%s\n' "$_result" | grep -oE '<[A-Z_0-9]+>' | sort -u || true)
    if [ -n "$_unresolved" ]; then
        echo "WARNING: $_rel has unresolved placeholders: $_unresolved" >&2
        _rc=1
    fi

    case "$MODE" in
        dryrun)
            echo "=== $_rel ==="
            printf '%s\n' "$_result" | diff -u "$_src" - || true
            ;;
        apply)
            printf '%s\n' "$_result" > "$_src"
            echo "OK: $_rel"
            ;;
        install)
            _dest="${INSTALL_PREFIX}/${_rel}"
            mkdir -p "$(dirname "$_dest")"
            printf '%s\n' "$_result" > "$_dest"
            echo "OK: $_rel -> $_dest"
            ;;
    esac
done

if [ "$_rc" -ne 0 ]; then
    echo "Some placeholders could not be resolved — check network.conf." >&2
fi
exit $_rc
