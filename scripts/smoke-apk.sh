#!/usr/bin/env bash
# SPDX-License-Identifier: MIT

set -euo pipefail

apk_bin="${1:?path to the SDK apk tool is required}"
package_dir="${2:?package directory is required}"

newt_apk="$(find "$package_dir" -maxdepth 1 -type f -name 'pangolin-newt-*.apk' -print -quit)"
luci_apk="$(find "$package_dir" -maxdepth 1 -type f -name 'luci-app-pangolin-newt-*.apk' -print -quit)"
[[ -n "$newt_apk" && -n "$luci_apk" ]]

"$apk_bin" adbdump --format json "$newt_apk" >/dev/null
"$apk_bin" adbdump --format json "$luci_apk" >/dev/null

extract_root="$(mktemp -d)"
trap 'rm -rf "$extract_root"' EXIT
mkdir -p "$extract_root/newt" "$extract_root/luci"

# apk(8) manifest queries installed packages and therefore needs an APK
# database.  For build artifacts, extract the v3 package directly and inspect
# the resulting tree instead.
"$apk_bin" --allow-untrusted extract --no-chown \
	--destination "$extract_root/newt" "$newt_apk" >/dev/null
"$apk_bin" --allow-untrusted extract --no-chown \
	--destination "$extract_root/luci" "$luci_apk" >/dev/null

for path in usr/bin/newt etc/init.d/newt etc/config/newt usr/libexec/newt-run usr/libexec/newt-migrate; do
	test -e "$extract_root/newt/$path"
done

for path in \
	usr/share/luci/menu.d/luci-app-pangolin-newt.json \
	usr/share/rpcd/acl.d/luci-app-pangolin-newt.json \
	usr/share/rpcd/ucode/pangolin-newt.uc \
	www/luci-static/resources/view/pangolin-newt/overview.js; do
	test -e "$extract_root/luci/$path"
done

echo 'APK metadata and package contents look correct.'
