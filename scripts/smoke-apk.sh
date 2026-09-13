#!/usr/bin/env bash
# SPDX-License-Identifier: MIT

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
source "$repo_root/versions.env"

apk_bin="${1:?path to the SDK apk tool is required}"
package_dir="${2:?package directory is required}"

newt_apk="$package_dir/pangolin-newt-${NEWT_VERSION}-r${NEWT_RELEASE}.apk"
luci_apk="$package_dir/luci-app-pangolin-newt-${NEWT_VERSION}-r${NEWT_RELEASE}.apk"
luci_zt_apk="$package_dir/luci-app-zt-${LUCI_ZT_VERSION}-r${LUCI_ZT_RELEASE}.apk"
[[ -f "$newt_apk" && -f "$luci_apk" && -f "$luci_zt_apk" ]]

extract_root="$(mktemp -d)"
trap 'rm -rf "$extract_root"' EXIT
mkdir -p "$extract_root/newt" "$extract_root/luci" "$extract_root/luci-zt"

"$apk_bin" adbdump --format json "$newt_apk" >"$extract_root/newt-metadata.json"
"$apk_bin" adbdump --format json "$luci_apk" >"$extract_root/luci-metadata.json"
"$apk_bin" adbdump --format json "$luci_zt_apk" >"$extract_root/luci-zt-metadata.json"
grep -Fq 'newt-launcher-migration-' "$extract_root/newt-metadata.json"

# apk(8) manifest queries installed packages and therefore needs an APK
# database.  For build artifacts, extract the v3 package directly and inspect
# the resulting tree instead.
"$apk_bin" --allow-untrusted extract --no-chown \
	--destination "$extract_root/newt" "$newt_apk" >/dev/null
"$apk_bin" --allow-untrusted extract --no-chown \
	--destination "$extract_root/luci" "$luci_apk" >/dev/null
"$apk_bin" --allow-untrusted extract --no-chown \
	--destination "$extract_root/luci-zt" "$luci_zt_apk" >/dev/null

for path in usr/bin/newt etc/init.d/newt etc/config/newt usr/libexec/newt-run usr/libexec/newt-migrate; do
	test -e "$extract_root/newt/$path"
done

if grep -Eq '^set -[^[:space:]]*u' "$extract_root/newt/usr/libexec/newt-run"; then
	echo 'Packaged newt-run enables nounset and is unsafe with OpenWrt shell helpers.' >&2
	exit 1
fi

for path in \
	etc/init.d/pangolin-newt-update \
	usr/libexec/pangolin-newt-update \
	usr/share/luci/menu.d/luci-app-pangolin-newt.json \
	usr/share/rpcd/acl.d/luci-app-pangolin-newt.json \
	usr/share/rpcd/ucode/pangolin-newt.uc \
	www/luci-static/resources/view/pangolin-newt/overview.js; do
	test -e "$extract_root/luci/$path"
done

grep -Fq 'get_package_status' "$extract_root/luci/usr/share/rpcd/ucode/pangolin-newt.uc"
grep -Fq 'package_action' "$extract_root/luci/usr/share/rpcd/ucode/pangolin-newt.uc"
grep -Fq 'boot()' "$extract_root/luci/etc/init.d/pangolin-newt-update"
test -x "$extract_root/luci/etc/init.d/pangolin-newt-update"
test -x "$extract_root/luci/usr/libexec/pangolin-newt-update"

for path in \
	etc/init.d/luci-app-zt-update \
	usr/libexec/luci-app-zt-update \
	usr/share/luci/menu.d/luci-app-zt.json \
	usr/share/rpcd/acl.d/luci-app-zt.json \
	usr/share/rpcd/ucode/luci-app-zt.uc \
	www/luci-static/resources/view/zt/overview.js; do
	test -e "$extract_root/luci-zt/$path"
done

grep -Fq 'get_networks' "$extract_root/luci-zt/usr/share/rpcd/ucode/luci-app-zt.uc"
grep -Fq 'set_config' "$extract_root/luci-zt/usr/share/rpcd/ucode/luci-app-zt.uc"
grep -Fq 'upgrade_zerotier' "$extract_root/luci-zt/usr/libexec/luci-app-zt-update"
grep -Fq 'upgrade_luci' "$extract_root/luci-zt/usr/libexec/luci-app-zt-update"
grep -Fq 'boot()' "$extract_root/luci-zt/etc/init.d/luci-app-zt-update"
test -x "$extract_root/luci-zt/etc/init.d/luci-app-zt-update"
test -x "$extract_root/luci-zt/usr/libexec/luci-app-zt-update"
grep -Fq 'luci-app-zerotier' "$extract_root/luci-zt-metadata.json"

echo 'APK metadata and package contents look correct.'
