#!/bin/sh
# SPDX-License-Identifier: MIT

set -eu

PROJECT_URL='https://github.com/DarthAnwalt/openwrt-newt'
REPOSITORY_BASE='https://DarthAnwalt.github.io/openwrt-newt/repository'
PUBLIC_KEY_URL="$REPOSITORY_BASE/openwrt-newt.pem"
PUBLIC_KEY_SHA256='7be0c3c59f76b7e1a4b893dc7b3ea71e574d5ac02d5290606092d34be19335b1'
OPENWRT_SERIES='25.12'
SUPPORTED_ARCH='aarch64_cortex-a53'
KEY_FILE='/etc/apk/keys/openwrt-newt.pem'
REPOSITORIES_FILE='/etc/apk/repositories.d/customfeeds.list'

fail() {
	printf 'openwrt-newt installer: %s\n' "$*" >&2
	exit 1
}

fetch() {
	url="$1"
	destination="$2"

	if command -v uclient-fetch >/dev/null 2>&1; then
		uclient-fetch -q -O "$destination" "$url"
	elif command -v wget >/dev/null 2>&1; then
		wget -q -O "$destination" "$url"
	else
		fail 'uclient-fetch or wget is required'
	fi
}

[ "$(id -u)" -eq 0 ] || fail 'run this command as root'
command -v apk >/dev/null 2>&1 || fail 'OpenWrt apk was not found'
command -v sha256sum >/dev/null 2>&1 || fail 'sha256sum was not found'
[ -r /etc/openwrt_release ] || fail '/etc/openwrt_release was not found'

# OpenWrt controls this file; it contains simple DISTRIB_* assignments.
# shellcheck disable=SC1091
. /etc/openwrt_release
release="${DISTRIB_RELEASE:-unknown}"
case "$release" in
	25.12|25.12.*|25.12-*) ;;
	*) fail "OpenWrt $OPENWRT_SERIES.x is required; this device reports $release" ;;
esac

[ -r /etc/apk/arch ] || fail '/etc/apk/arch was not found'
arch="$(sed -n '1p' /etc/apk/arch)"
[ "$arch" = "$SUPPORTED_ARCH" ] || \
	fail "unsupported package architecture $arch (expected $SUPPORTED_ARCH)"

key_tmp="$(mktemp /tmp/openwrt-newt-key.XXXXXX)"
trap 'rm -f "$key_tmp"' EXIT HUP INT TERM

printf 'Downloading and verifying the repository public key...\n'
fetch "$PUBLIC_KEY_URL" "$key_tmp"
printf '%s  %s\n' "$PUBLIC_KEY_SHA256" "$key_tmp" | sha256sum -c - >/dev/null || \
	fail 'repository public key checksum mismatch'

mkdir -p "$(dirname "$KEY_FILE")" "$(dirname "$REPOSITORIES_FILE")"
cp "$key_tmp" "$KEY_FILE"
chmod 0644 "$KEY_FILE"

repository="$REPOSITORY_BASE/$OPENWRT_SERIES/$arch/packages.adb"
touch "$REPOSITORIES_FILE"
if ! grep -Fqx "$repository" "$REPOSITORIES_FILE"; then
	printf '%s\n' "$repository" >>"$REPOSITORIES_FILE"
fi

printf 'Refreshing package indexes and installing Newt...\n'
apk update
apk add pangolin-newt luci-app-pangolin-newt

printf '\nInstallation complete. Open LuCI and choose Services -> Newt.\n'
printf 'Project and troubleshooting: %s\n' "$PROJECT_URL"
