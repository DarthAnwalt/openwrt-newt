#!/bin/sh
# SPDX-License-Identifier: MIT

set -eu

migrate=0
case "${1:-}" in
	'') ;;
	--migrate) migrate=1 ;;
	--help)
		printf '%s\n' 'Usage: install.sh [--migrate]'
		printf '%s\n' '  --migrate  back up and migrate an existing manual Newt installation'
		exit 0
		;;
	*) printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
esac

PROJECT_URL='https://github.com/DarthAnwalt/openwrt-newt'
REPOSITORY_BASE='https://DarthAnwalt.github.io/openwrt-newt/repository'
PUBLIC_KEY_URL="$REPOSITORY_BASE/openwrt-newt.pem"
PUBLIC_KEY_SHA256='7be0c3c59f76b7e1a4b893dc7b3ea71e574d5ac02d5290606092d34be19335b1'
OPENWRT_SERIES='25.12'
SUPPORTED_ARCH='aarch64_cortex-a53'
KEY_FILE='/etc/apk/keys/openwrt-newt.pem'
REPOSITORIES_FILE='/etc/apk/repositories.d/customfeeds.list'
LEGACY_CONFIG='/root/.config/newt-client/config.json'
PACKAGE_INIT='/etc/init.d/newt'

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

is_package_init() {
	[ -r "$PACKAGE_INIT" ] && grep -Fq '/usr/libexec/newt-run' "$PACKAGE_INIT"
}

package_is_installed() {
	apk query --from installed --fields name --format json pangolin-newt 2>/dev/null |
		jsonfilter -e '@[*].name' 2>/dev/null |
		grep -Fxq 'pangolin-newt'
}

legacy_has_value() {
	[ -n "$(jsonfilter -i "$LEGACY_CONFIG" -e "$1" 2>/dev/null)" ]
}

uci_has_value() {
	[ -n "$(uci -q get "$1" 2>/dev/null)" ]
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

printf 'Refreshing package indexes...\n'
apk update

installed=0
package_is_installed && installed=1
move_init=0
legacy_detected=0

if [ -e "$PACKAGE_INIT" ] && { [ "$installed" -eq 0 ] || ! is_package_init; }; then
	move_init=1
	legacy_detected=1
elif [ "$installed" -eq 0 ] && { [ -e /usr/bin/newt ] || [ -e "$LEGACY_CONFIG" ]; }; then
	legacy_detected=1
fi

if [ "$legacy_detected" -eq 1 ] && [ "$migrate" -ne 1 ]; then
	fail 'a manual Newt installation was found; rerun this installer with --migrate'
fi

backup=''
was_running=0
was_enabled=0

if [ "$legacy_detected" -eq 1 ]; then
	[ -r "$LEGACY_CONFIG" ] || fail "legacy configuration $LEGACY_CONFIG is not readable"
	legacy_has_value '@.endpoint' || \
		fail 'legacy configuration has no endpoint'
	legacy_has_value '@.id' || \
		fail 'legacy configuration has no id'
	legacy_has_value '@.secret' || \
		fail 'legacy configuration has no secret'

	umask 077
	backup="/root/newt-manual-backup-$(date +%Y%m%d-%H%M%S)-$$"
	mkdir -m 0700 "$backup"
	[ ! -e /usr/bin/newt ] || cp -p /usr/bin/newt "$backup/newt"
	cp -p "$LEGACY_CONFIG" "$backup/config.json"
	chmod 0600 "$LEGACY_CONFIG" "$backup/config.json"

	if [ -e "$PACKAGE_INIT" ]; then
		/etc/init.d/newt running >/dev/null 2>&1 && was_running=1
		/etc/init.d/newt enabled >/dev/null 2>&1 && was_enabled=1
		cp -p "$PACKAGE_INIT" "$backup/newt.init"
	fi

	printf 'Legacy installation backed up to %s\n' "$backup"
	if [ "$move_init" -eq 1 ]; then
		/etc/init.d/newt stop 2>/dev/null || true
		mv "$PACKAGE_INIT" "$backup/newt.init.active"
	fi
fi

printf 'Installing or upgrading Newt packages...\n'
if ! apk add --upgrade --latest pangolin-newt luci-app-pangolin-newt; then
	if [ -n "$backup" ] && [ -e "$backup/newt.init.active" ]; then
		[ ! -e "$backup/newt" ] || cp "$backup/newt" /usr/bin/newt
		[ ! -e "$backup/newt" ] || chmod 0755 /usr/bin/newt
		cp "$backup/newt.init.active" "$PACKAGE_INIT"
		chmod 0755 "$PACKAGE_INIT"
		[ "$was_enabled" -eq 0 ] || /etc/init.d/newt enable
		[ "$was_running" -eq 0 ] || /etc/init.d/newt start
	fi
	fail 'package installation failed; the legacy launcher was restored'
fi

# APK protects locally created files under /etc by placing the packaged copy
# next to them as .apk-new. The installer moves the old launcher away before a
# first install, and this fallback repairs installations made with older
# versions of this script.
if ! is_package_init && [ -r "$PACKAGE_INIT.apk-new" ]; then
	[ -n "$backup" ] || {
		umask 077
		backup="/root/newt-manual-backup-$(date +%Y%m%d-%H%M%S)-$$"
		mkdir -m 0700 "$backup"
		[ ! -e "$PACKAGE_INIT" ] || cp -p "$PACKAGE_INIT" "$backup/newt.init"
	}
	cp "$PACKAGE_INIT.apk-new" "$PACKAGE_INIT"
	chmod 0755 "$PACKAGE_INIT"
fi

is_package_init || fail 'the packaged procd launcher was not installed'

if [ -n "$backup" ] && [ -e "$PACKAGE_INIT.apk-new" ]; then
	mv "$PACKAGE_INIT.apk-new" "$backup/newt.init.apk-new"
fi

if [ "$migrate" -eq 1 ]; then
	if uci_has_value newt.main.endpoint && \
	   uci_has_value newt.main.id && \
	   uci_has_value newt.main.secret; then
		printf 'Existing UCI credentials retained.\n'
		/etc/init.d/newt enable
		/etc/init.d/newt restart
	else
		/usr/libexec/newt-migrate --check
		/usr/libexec/newt-migrate --apply
	fi
fi

printf '\nInstallation complete. Open LuCI and choose Services -> Newt.\n'
[ -z "$backup" ] || printf 'Legacy backup retained at %s\n' "$backup"
printf 'Project and troubleshooting: %s\n' "$PROJECT_URL"
