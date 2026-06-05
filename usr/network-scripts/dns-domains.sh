#!/bin/sh
# dns-domains.sh — Unified DNS forwarding list generator for BIND9 and dnsmasq
#
# Usage:
#   dns-domains.sh --format=bind9    # BIND9 zone forwarding → named.conf.gfwlist, named.conf.ggcn
#   dns-domains.sh --format=dnsmasq  # dnsmasq server= rules → /etc/dnsmasq.d/domains.gfwlist
#
set -eu
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

FORMAT=""
for arg in "$@"; do
    case "$arg" in
        --format=*) FORMAT="${arg#--format=}" ;;
        bind9|dnsmasq) FORMAT="$arg" ;;
        *) echo "Unknown argument: $arg" >&2; exit 1 ;;
    esac
done

if [ -z "$FORMAT" ]; then
    echo "Usage: $0 --format=bind9|dnsmasq" >&2
    exit 1
fi

case "$FORMAT" in
    bind9|dnsmasq) ;;
    *) echo "Invalid format: $FORMAT (expected bind9 or dnsmasq)" >&2; exit 1 ;;
esac

DIR_SCRIPTS="$(cd "$(dirname "$0")" && pwd)"
DOMAINS_LOCAL="${DIR_SCRIPTS}/domains.localadd"
DOMAINS_LOCAL_US="${DIR_SCRIPTS}/domains.localadd_us"

CONF_FILE="${DIR_SCRIPTS}/network.conf"
if [ ! -f "$CONF_FILE" ]; then
    echo "ERROR: $CONF_FILE not found. Copy network.conf.template and fill in values." >&2
    exit 1
fi
. "$CONF_FILE"

GFWLIST_URL="https://raw.githubusercontent.com/gfwlist/gfwlist/master/gfwlist.txt"
GOOGLE_CHINA_URL="https://raw.githubusercontent.com/felixonmars/dnsmasq-china-list/master/google.china.conf"

# Sanity floor: gfwlist normally yields several thousand domains. A result far
# below this means a partial or poisoned fetch (raw.githubusercontent.com is
# itself frequently blocked), so warn loudly rather than silently deploying a
# degraded config.
GFWLIST_MIN=1000

FWD_GLOBAL_BIND9="1.1.1.1; 8.8.8.8; 8.8.4.4; 1.0.0.1;"
# FWD_US_BIND9 loaded from network.conf
FWD_CHINA_BIND9="119.29.29.29; 182.254.118.118; 223.5.5.5; 223.6.6.6; "

FWD_DNSMASQ_1="8.8.4.4"
FWD_DNSMASQ_2="8.8.8.8"

BIND9_OUT_GFW="/etc/bind/named.conf.gfwlist"
BIND9_OUT_GGCN="/etc/bind/named.conf.ggcn"
DNSMASQ_OUT="/etc/dnsmasq.d/domains.gfwlist"

TMP_DIR="${TMPDIR:-/tmp}"
LIST_TMP="${TMP_DIR}/dns-domains.$$.tmp"
LIST_WORK="${TMP_DIR}/dns-domains.$$.work"

cleanup() {
    rm -f "$LIST_TMP" "$LIST_WORK" "${LIST_WORK}.out" \
          "${BIND9_OUT_GFW}.new" "${BIND9_OUT_GGCN}.new" "${DNSMASQ_OUT}.new"
}
trap cleanup EXIT

# --- Shared fetch/parse ---------------------------------------------------

fetch_gfwlist() {
    wget -4qO- "$GFWLIST_URL" \
        | base64 -d \
        | sed -e '/^!/d' -e '/^\[/d' -e '/^@/d' -e '/%/d' -e '/^$/d' \
              -e 's/[[:space:]]*$//' -e 's/^[[:space:]]*//' \
              -e 's/^|*//' -e 's#^https\?://##' -e 's/^\.//' \
        | cut -d'/' -f1 \
        | sed -e 's/[^.]*\*[^.]*\.//g' -e 's/\*//g' \
        | grep -E '^([A-Za-z0-9_-]+\.)+([A-Za-z]{2,}|xn--[A-Za-z0-9-]+)$' \
        | grep -v '^[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}$' \
        | sort -u
}

fetch_google_china() {
    wget -4qO- "$GOOGLE_CHINA_URL" \
        | cut -d'/' -f2 \
        | sed '/^$/d;/^#/d'
}

# Returns 0 if the gfwlist in $1 is usable, non-zero (with a warning) if it is
# empty or suspiciously short — the caller then keeps the last-good output
# instead of overwriting it with a degraded list.
check_gfwlist() {
    count=$(wc -l < "$1")
    if [ "$count" -eq 0 ]; then
        echo "WARNING: gfwlist fetch returned empty result; keeping existing config" >&2
        return 1
    fi
    if [ "$count" -lt "$GFWLIST_MIN" ]; then
        echo "WARNING: gfwlist returned only $count domains (expected >= $GFWLIST_MIN); the fetch is likely partial or poisoned, keeping existing config" >&2
        return 1
    fi
    return 0
}

# --- BIND9 output ---------------------------------------------------------

# Domains excluded from BIND9 forwarding so they resolve via the default path
# (e.g. routed through a US gateway instead of global DNS forwarders).
BIND9_EXCLUSIONS='/openai.com/d;/chatgpt.com/d;/oaistatic.com/d;/oaiusercontent.com/d;/gemini.google.com/d;/x.ai/d;/grok.com/d;/linkedin.com/d;/docker.com/d;/gitlab.com/d;/docker.io/d;'

generate_bind9() {
    rm -f "$LIST_TMP" "$LIST_WORK"

    # gfwlist + localadd → BIND9_OUT_GFW, promoted only if gfwlist is healthy.
    fetch_gfwlist > "$LIST_TMP"
    if check_gfwlist "$LIST_TMP"; then
        grep -v '#' "$DOMAINS_LOCAL" | while read -r line; do
            [ -z "$line" ] && continue
            printf 'zone "%s" { type forward; forward only; forwarders {%s};};\n' "$line" "$FWD_GLOBAL_BIND9"
        done > "$LIST_WORK"

        grep -v '#' "$DOMAINS_LOCAL_US" | while read -r line; do
            [ -z "$line" ] && continue
            printf 'zone "%s" { type forward; forward only; forwarders {%s};};\n' "$line" "$FWD_US_BIND9"
        done >> "$LIST_WORK"

        # github domains excluded from gfwlist (handled via domains.localadd_us)
        grep -v github "$LIST_TMP" \
            | sed "s/^/zone \"/;s/$/\" { type forward; forward only; forwarders {${FWD_GLOBAL_BIND9}};};/" \
            >> "$LIST_WORK"

        sort "$LIST_WORK" | uniq | sed "$BIND9_EXCLUSIONS" > "${BIND9_OUT_GFW}.new"
        mv "${BIND9_OUT_GFW}.new" "$BIND9_OUT_GFW"
    fi

    # google.china → BIND9_OUT_GGCN, promoted only if the fetch is non-empty.
    fetch_google_china > "$LIST_TMP"
    if [ -s "$LIST_TMP" ]; then
        sed "s/^/zone \"/;s/$/\" { type forward; forward only; forwarders {${FWD_CHINA_BIND9}};};/" "$LIST_TMP" \
            | sort | uniq > "${BIND9_OUT_GGCN}.new"
        mv "${BIND9_OUT_GGCN}.new" "$BIND9_OUT_GGCN"
    else
        echo "WARNING: google.china fetch returned empty result; keeping existing $BIND9_OUT_GGCN" >&2
    fi

    rm -f "$LIST_TMP" "$LIST_WORK"

    if ! named-checkconf; then
        echo "ERROR: named-checkconf failed, skipping reload" >&2
        exit 1
    fi
    rndc reload
}

# --- dnsmasq output -------------------------------------------------------
# dnsmasq output is NOT sorted — order matches the original: all entries with
# forwarder 1, then all with forwarder 2, then localadd entries appended.

generate_dnsmasq() {
    rm -f "$LIST_TMP" "$LIST_WORK"

    fetch_gfwlist > "$LIST_TMP"
    if ! check_gfwlist "$LIST_TMP"; then
        echo "WARNING: keeping existing $DNSMASQ_OUT, skipping dnsmasq restart" >&2
        rm -f "$LIST_TMP"
        return
    fi
    sed "s/^/server=\//;s/$/\/${FWD_DNSMASQ_1}/" "$LIST_TMP" > "$LIST_WORK"
    sed "s/^/server=\//;s/$/\/${FWD_DNSMASQ_2}/" "$LIST_TMP" >> "$LIST_WORK"

    grep -v '#' "$DOMAINS_LOCAL" | while read -r line; do
        [ -z "$line" ] && continue
        printf 'server=/%s/%s\n' "$line" "$FWD_DNSMASQ_1"
        printf 'server=/%s/%s\n' "$line" "$FWD_DNSMASQ_2"
    done >> "$LIST_WORK"

    mv "$LIST_WORK" "$DNSMASQ_OUT"

    rm -f "$LIST_TMP"
    service dnsmasq restart
}

# --- Main -----------------------------------------------------------------

case "$FORMAT" in
    bind9)   generate_bind9 ;;
    dnsmasq) generate_dnsmasq ;;
esac
