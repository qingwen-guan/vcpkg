#!/usr/bin/env bash
# Used as vcpkg asset source: x-script,bash /path/to/vcpkg-download-github-mirror.sh {url} {dst}
# Tries GitHub (and api.github.com) mirrors first, then the original URL.
set -euo pipefail

ORIG_URL="${1:?missing url}"
DST="${2:?missing dst}"

try_curl() {
    local url="$1"
    curl -fL \
        --connect-timeout "${VCPKG_CURL_CONNECT_TIMEOUT:-30}" \
        --max-time "${VCPKG_CURL_MAX_TIME:-1800}" \
        --retry "${VCPKG_CURL_RETRY:-2}" \
        --retry-delay 2 \
        -o "$DST" \
        "$url"
}

# Optional: space-separated full URL prefixes (each is prepended before ORIG_URL, or used as-is if it ends with /)
# Example: VCPKG_GITHUB_MIRROR_PREFIXES="https://ghproxy.net/ https://gh.llkk.cc/"
if [[ -n "${VCPKG_GITHUB_MIRROR_PREFIXES:-}" ]]; then
    read -r -a MIRROR_PREFIXES <<<"${VCPKG_GITHUB_MIRROR_PREFIXES}"
else
    MIRROR_PREFIXES=(
        "https://ghproxy.net/"
        "https://gh.llkk.cc/"
        "https://mirror.ghproxy.com/"
    )
fi

if [[ "$ORIG_URL" =~ ^https://(github\.com|api\.github\.com)/ ]]; then
    for prefix in "${MIRROR_PREFIXES[@]}"; do
        mirror_url="${prefix}${ORIG_URL}"
        if try_curl "$mirror_url" 2>/dev/null; then
            exit 0
        fi
    done
fi

try_curl "$ORIG_URL"
exit 0
