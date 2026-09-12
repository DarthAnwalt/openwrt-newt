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

newt_manifest="$("$apk_bin" manifest --allow-untrusted "$newt_apk")"
luci_manifest="$("$apk_bin" manifest --allow-untrusted "$luci_apk")"

for path in usr/bin/newt etc/init.d/newt etc/config/newt usr/libexec/newt-run usr/libexec/newt-migrate; do
	grep -q "  $path$" <<<"$newt_manifest"
done

for path in \
	usr/share/luci/menu.d/luci-app-pangolin-newt.json \
	usr/share/rpcd/acl.d/luci-app-pangolin-newt.json \
	usr/share/rpcd/ucode/pangolin-newt.uc \
	www/luci-static/resources/view/pangolin-newt/overview.js; do
	grep -q "  $path$" <<<"$luci_manifest"
done

echo 'APK metadata and package contents look correct.'
