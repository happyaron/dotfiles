#!/usr/bin/env python3
"""
Generate a full list of domain names used when accessing gemini.google.com.

Sources:
  - Google Workspace Admin: "Gemini app firewall settings"
    https://support.google.com/a/answer/15627649
  - Observed network traffic (authentication, API, telemetry, assets)
"""

import json


# ---------------------------------------------------------------------------
# Official Gemini hosts from Google Workspace Admin firewall guide
# https://support.google.com/a/answer/15627649
# ---------------------------------------------------------------------------
OFFICIAL_GEMINI_HOSTS = [
    "gemini.google.com",                    # Gemini web app
    "apis.google.com",                      # Google APIs loader
    "www.googleapis.com",                   # Google APIs
    "jnn-pa.googleapis.com",                # Gemini streaming/proactive backend
    "waa-pa.clients6.google.com",           # Web app analytics
    "ogads-pa.clients6.google.com",         # Ad-related telemetry
    "optimizationguide-pa.googleapis.com",  # Chrome optimization hints
    "content-autofill.googleapis.com",      # Autofill service
    "streetviewpixels-pa.googleapis.com",   # Street View imagery
    "maps.googleapis.com",                  # Maps API (location features)
    "maps.gstatic.com",                     # Maps static assets
    "www.google.com",                       # Google base (auth, search)
    "ogs.google.com",                       # Google search suggestions
    "play.google.com",                      # Play Store references
    "www.youtube.com",                      # YouTube embeds
    "i.ytimg.com",                          # YouTube thumbnails
    "yt3.ggpht.com",                        # YouTube channel avatars
    "fonts.googleapis.com",                 # Google Fonts CSS
    "fonts.gstatic.com",                    # Google Fonts files
    "ssl.gstatic.com",                      # SSL-served static assets
    "www.gstatic.com",                      # General static assets
    "encrypted-tbn0.gstatic.com",           # Encrypted thumbnail server 0
    "encrypted-tbn1.gstatic.com",           # Encrypted thumbnail server 1
    "encrypted-tbn2.gstatic.com",           # Encrypted thumbnail server 2
    "encrypted-tbn3.gstatic.com",           # Encrypted thumbnail server 3
    "lh3.googleusercontent.com",            # User-uploaded content / avatars
    "lh3.google.com",                       # Google-hosted images
    "lh5.googleusercontent.com",            # User content (Maps imagery)
    "www.googletagmanager.com",             # Google Tag Manager
    "www.google-analytics.com",             # Google Analytics
    "static.doubleclick.net",               # DoubleClick static assets
    "td.doubleclick.net",                   # DoubleClick tracking
    "googleads.g.doubleclick.net",          # Google Ads / DoubleClick
    "csp.withgoogle.com",                   # Content Security Policy reporting
]

# ---------------------------------------------------------------------------
# Additional domains observed in browser network traffic and required for
# full Gemini functionality (auth, APIs, telemetry, extensions, etc.)
# ---------------------------------------------------------------------------
ADDITIONAL_OBSERVED_DOMAINS = [
    # --- Authentication & Accounts ---
    "accounts.google.com",                  # Google Sign-In / OAuth
    "myaccount.google.com",                 # Account management
    "accounts.youtube.com",                 # YouTube account auth
    "oauth2.googleapis.com",                # OAuth2 token endpoint
    "securetoken.googleapis.com",           # Firebase / secure token

    # --- Gemini API & Backend ---
    "generativelanguage.googleapis.com",    # Gemini API (GenerateContent)
    "alkalimakersuite-pa.clients6.google.com",  # Gemini/AI Studio backend
    "alkali-pa.clients6.google.com",        # Gemini proactive backend
    "proactivebackend-pa.googleapis.com",   # Proactive suggestions backend
    "notifications-pa.googleapis.com",      # Push notifications

    # --- Static Assets & CDN ---
    "lh4.googleusercontent.com",            # User content variant
    "lh6.googleusercontent.com",            # User content variant
    "storage.googleapis.com",               # Cloud Storage (uploaded files)
    "www.google.com.hk",                    # Regional Google variant

    # --- Telemetry & Logging ---
    "play.google.com",                      # (also in official list)
    "pagead2.googlesyndication.com",        # Ad syndication
    "adservice.google.com",                 # Ad service
    "clients1.google.com",                  # Client telemetry
    "clients2.google.com",                  # Client telemetry
    "clients4.google.com",                  # Client telemetry
    "clients6.google.com",                  # Client telemetry
    "update.googleapis.com",                # Chrome / component updates
    "clientservices.googleapis.com",        # Client services

    # --- Extensions & Connected Services ---
    "workspace.google.com",                 # Workspace integration
    "drive.google.com",                     # Google Drive (file references)
    "docs.google.com",                      # Google Docs integration
    "mail.google.com",                      # Gmail integration
    "calendar.google.com",                  # Calendar integration
    "keep.google.com",                      # Google Keep integration
    "tasks.googleapis.com",                 # Google Tasks API

    # --- Other Infrastructure ---
    "id.google.com",                        # Identity services
    "signaler-pa.clients6.google.com",      # Real-time signaling
    "people-pa.clients6.google.com",        # People API (contacts)
    "blobcomments-pa.clients6.google.com",  # Blob/comments backend
]


def get_all_domains() -> list[str]:
    """Return a deduplicated, sorted list of all Gemini-related domains."""
    all_domains = set(OFFICIAL_GEMINI_HOSTS) | set(ADDITIONAL_OBSERVED_DOMAINS)
    return sorted(all_domains)


def main():
    import argparse

    parser = argparse.ArgumentParser(
        description="Generate the list of domains used by gemini.google.com"
    )
    parser.add_argument(
        "-f", "--format",
        choices=["plain", "json", "dnsmasq", "hosts"],
        default="plain",
        help="Output format (default: plain)",
    )
    parser.add_argument(
        "--official-only",
        action="store_true",
        help="Only output official Google-documented Gemini hosts",
    )
    args = parser.parse_args()

    if args.official_only:
        domains = sorted(set(OFFICIAL_GEMINI_HOSTS))
    else:
        domains = get_all_domains()

    if args.format == "plain":
        for d in domains:
            print(d)

    elif args.format == "json":
        print(json.dumps(domains, indent=2))

    elif args.format == "dnsmasq":
        # dnsmasq server= lines (useful for split-DNS routing)
        print("# Gemini domains for dnsmasq")
        for d in domains:
            print(f"server=/{d}/8.8.8.8")

    elif args.format == "hosts":
        # /etc/hosts style (block or redirect)
        print("# Gemini domains")
        for d in domains:
            print(f"0.0.0.0 {d}")


if __name__ == "__main__":
    main()
