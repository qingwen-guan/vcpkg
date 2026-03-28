#!/usr/bin/env bash
# Install common dependencies when direct GitHub access is slow or blocked.
#
# What it does:
#   1. Sets X_VCPKG_ASSET_SOURCES so tarball downloads try public mirrors, then the original URL.
#   2. Forwards common proxy env vars to curl (https_proxy / HTTPS_PROXY / ALL_PROXY).
#   3. Optionally configures a one-shot git URL rewrite for github.com (clone/fetch).
#
# Usage (from vcpkg root):
#   ./install-with-github-mirror.sh
#   ./install-with-github-mirror.sh spdlog gtest
#   HTTPS_PROXY=http://127.0.0.1:7890 ./install-with-github-mirror.sh
#
# Env:
#   VCPKG_GITHUB_MIRROR_PREFIXES — space-separated mirror URL prefixes (prepended to full URL).
#     Default tries ghproxy.net, gh.llkk.cc, mirror.ghproxy.com.
#   VCPKG_USE_GIT_MIRROR — if set to 1, set git url.<mirror>.insteadOf for this run (restored on exit).
#   VCPKG_GIT_MIRROR_PREFIX — replacement base URL, default https://ghproxy.net/https://github.com/
#
set -euo pipefail

vcpkg_root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
vcpkg_exe="${vcpkg_root}/vcpkg"
fetch_helper="${vcpkg_root}/scripts/vcpkg-download-github-mirror.sh"

if [ ! -x "$vcpkg_exe" ] && [ -f "$vcpkg_exe" ]; then
    chmod +x "$vcpkg_exe" || true
fi
if [ ! -f "$vcpkg_exe" ]; then
    echo "vcpkg binary not found at $vcpkg_exe — run ./bootstrap-vcpkg.sh or ./bootstrap-vcpkg-mirror.sh first." >&2
    exit 1
fi
if [ ! -f "$fetch_helper" ]; then
    echo "Missing $fetch_helper" >&2
    exit 1
fi
chmod +x "$fetch_helper" 2>/dev/null || true

DEFAULT_PORTS=(spdlog gtest nlohmann-json mongo-cxx-driver curl hiredis)
if [ "$#" -gt 0 ]; then
    ports=("$@")
else
    ports=("${DEFAULT_PORTS[@]}")
fi

# x-script: commas in value must be escaped with backtick per vcpkg assetcaching rules.
# Use absolute path so it works from any cwd.
asset_source="x-script,bash ${fetch_helper} {url} {dst}"
export X_VCPKG_ASSET_SOURCES="${X_VCPKG_ASSET_SOURCES:-}${X_VCPKG_ASSET_SOURCES:+;}${asset_source}"

if [ "${VCPKG_USE_GIT_MIRROR:-0}" = "1" ]; then
    git_mirror_base="${VCPKG_GIT_MIRROR_PREFIX:-https://ghproxy.net/https://github.com/}"
    git config --global url."${git_mirror_base}".insteadOf "https://github.com/"
    _vcpkg_restore_git_insteadof() {
        git config --global --unset url."${git_mirror_base}".insteadOf 2>/dev/null || true
    }
    trap _vcpkg_restore_git_insteadof EXIT
fi

echo "Installing: ${ports[*]}"
echo "Asset source: custom bash helper (GitHub mirrors + fallback). Override mirrors with VCPKG_GITHUB_MIRROR_PREFIXES."
echo "Tip: export HTTPS_PROXY=http://your-proxy:port if downloads still fail."

exec "$vcpkg_exe" install "${ports[@]}"
