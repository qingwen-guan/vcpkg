#!/bin/sh
# Workaround when ./bootstrap-vcpkg.sh hangs at "Downloading vcpkg-glibc..." (GitHub slow/blocked).
# - Shows download progress (unlike silent curl in scripts/bootstrap.sh)
# - Tries GitHub then common mirror URL prefixes (set VCPKG_URL_PREFIXES to override)
# - Skips download if ./vcpkg already matches the expected SHA512
# Usage: ./bootstrap-vcpkg-mirror.sh [-disableMetrics]
#
# Optional env:
#   HTTPS_PROXY / https_proxy / ALL_PROXY — forwarded to curl
#   VCPKG_URL_PREFIXES — space-separated mirrors: each item is either a full asset URL or a prefix like https://ghproxy.net/https://github.com
#     Example: VCPKG_URL_PREFIXES="https://ghproxy.net/https://github.com https://github.com"

set -e

vcpkgRootDir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
METADATA="$vcpkgRootDir/scripts/vcpkg-tool-metadata.txt"
if [ ! -f "$METADATA" ]; then
    echo "Cannot find $METADATA; run this script from the vcpkg root." >&2
    exit 1
fi

# shellcheck source=/dev/null
. "$METADATA"

vcpkgDisableMetrics="OFF"
for var in "$@"; do
    case "$var" in
        -disableMetrics|--disableMetrics) vcpkgDisableMetrics="ON" ;;
        -h|--help|-help)
            echo "Usage: $0 [-disableMetrics]"
            echo "See script header for VCPKG_URL_PREFIXES and proxy env vars."
            exit 0
            ;;
        *)
            echo "Unknown option: $var" >&2
            exit 1
            ;;
    esac
done

UNAME=$(uname)
ARCH=$(uname -m)
vcpkgUseMuslC="OFF"
if [ -e /etc/alpine-release ]; then
    vcpkgUseMuslC="ON"
fi

if [ "$UNAME" = "Darwin" ]; then
    echo "Target: vcpkg-macos"
    vcpkgToolReleaseSha=$VCPKG_MACOS_SHA
    vcpkgToolName="vcpkg-macos"
elif [ "$UNAME" = "Linux" ] && [ "$vcpkgUseMuslC" = "ON" ] && [ "$ARCH" = "x86_64" ]; then
    echo "Target: vcpkg-muslc"
    vcpkgToolReleaseSha=$VCPKG_MUSLC_SHA
    vcpkgToolName="vcpkg-muslc"
elif [ "$UNAME" = "Linux" ] && [ "$ARCH" = "x86_64" ]; then
    echo "Target: vcpkg-glibc"
    vcpkgToolReleaseSha=$VCPKG_GLIBC_SHA
    vcpkgToolName="vcpkg-glibc"
elif [ "$UNAME" = "Linux" ] && { [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; }; then
    echo "Target: vcpkg-glibc-arm64"
    vcpkgToolReleaseSha=$VCPKG_GLIBC_ARM64_SHA
    vcpkgToolName="vcpkg-glibc-arm64"
else
    echo "No prebuilt binary for this platform; use ./bootstrap-vcpkg.sh (build from source) or install cmake+ninja+git." >&2
    exit 1
fi

releasePath="microsoft/vcpkg-tool/releases/download/$VCPKG_TOOL_RELEASE_TAG/$vcpkgToolName"

sha512_of() {
    _f=$1
    if command -v sha512sum >/dev/null 2>&1; then
        sha512sum "$_f"
    elif command -v sha512 >/dev/null 2>&1; then
        sha512 -q "$_f"
    else
        shasum -a 512 "$_f"
    fi | awk '{print $1}'
}

if [ -f "$vcpkgRootDir/vcpkg" ]; then
    actual=$(sha512_of "$vcpkgRootDir/vcpkg")
    if [ "$actual" = "$vcpkgToolReleaseSha" ]; then
        echo "Existing ./vcpkg already matches expected SHA512; skipping download."
        chmod +x "$vcpkgRootDir/vcpkg"
    else
        echo "Existing ./vcpkg hash mismatch; will re-download." >&2
        rm -f "$vcpkgRootDir/vcpkg"
    fi
fi

if [ ! -f "$vcpkgRootDir/vcpkg" ]; then
    outPart="$vcpkgRootDir/vcpkg.part"
    rm -f "$outPart"
    ok=0

    # shellcheck disable=SC2086
    if [ -n "$VCPKG_URL_PREFIXES" ]; then
        urlCandidates=$VCPKG_URL_PREFIXES
    else
        urlCandidates="https://github.com/${releasePath} https://ghproxy.net/https://github.com/${releasePath} https://gh.llkk.cc/https://github.com/${releasePath}"
    fi

    for prefix in $urlCandidates; do
        case "$prefix" in
            http://*|https://*) ;;
            *) echo "Ignoring invalid entry: $prefix" >&2; continue ;;
        esac
        case "$prefix" in
            */microsoft/vcpkg-tool/releases/download/*)
                url=$prefix
                ;;
            *)
                url="${prefix%/}/$releasePath"
                ;;
        esac

        echo "Trying: $url"
        if curl -fL \
            --connect-timeout 25 \
            --max-time 1800 \
            --retry 3 \
            --retry-delay 2 \
            --progress-bar \
            --tlsv1.2 \
            -o "$outPart" \
            "$url"
        then
            actual=$(sha512_of "$outPart")
            if [ "$actual" = "$vcpkgToolReleaseSha" ]; then
                chmod +x "$outPart"
                mv -f "$outPart" "$vcpkgRootDir/vcpkg"
                ok=1
                echo "Download OK."
                break
            fi
            echo "SHA512 mismatch for this mirror; trying next." >&2
            rm -f "$outPart"
        else
            echo "Download failed from this URL; trying next." >&2
            rm -f "$outPart"
        fi
    done

    if [ "$ok" != 1 ]; then
        echo "All download attempts failed. Try:" >&2
        echo "  export https_proxy=http://127.0.0.1:7890   # your proxy" >&2
        echo "  VCPKG_URL_PREFIXES='https://ghproxy.net/https://github.com' $0" >&2
        exit 1
    fi
fi

"$vcpkgRootDir/vcpkg" version --disable-metrics

if [ "$vcpkgDisableMetrics" = "ON" ]; then
    touch "$vcpkgRootDir/vcpkg.disable-metrics"
elif ! [ -f "$vcpkgRootDir/vcpkg.disable-metrics" ]; then
    cat <<EOF
Telemetry
---------
vcpkg collects usage data in order to help us improve your experience.
The data collected by Microsoft is anonymous.
You can opt-out by re-running with -disableMetrics, passing --disable-metrics to vcpkg,
or setting VCPKG_DISABLE_METRICS.

Read more: docs/about/privacy.md
EOF
fi

echo "Done. Use: $vcpkgRootDir/vcpkg"
