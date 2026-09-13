#!/usr/bin/env bash
# SPDX-License-Identifier: MIT

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
source "$repo_root/versions.env"

apk_bin="${1:?path to the SDK apk tool is required}"
package_dir="${2:?package directory is required}"

newt_apk="$package_dir/pangolin-newt-${NEWT_VERSION}-r${NEWT_RELEASE}.apk"
luci_apk="$package_dir/luci-app-pangolin-newt-${NEWT_VERSION}-r${NEWT_RELEASE}.apk"
[[ -f "$newt_apk" && -f "$luci_apk" ]]

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

if grep -Eq '^set -[^[:space:]]*u' "$extract_root/newt/usr/libexec/newt-run"; then
	echo 'Packaged newt-run enables nounset and is unsafe with OpenWrt shell helpers.' >&2
	exit 1
fi

for path in \
	usr/share/luci/menu.d/luci-app-pangolin-newt.json \
	usr/share/rpcd/acl.d/luci-app-pangolin-newt.json \
	usr/share/rpcd/ucode/pangolin-newt.uc \
	www/luci-static/resources/view/pangolin-newt/overview.js; do
	test -e "$extract_root/luci/$path"
done

grep -Fq 'get_package_status' "$extract_root/luci/usr/share/rpcd/ucode/pangolin-newt.uc"
grep -Fq 'package_action' "$extract_root/luci/usr/share/rpcd/ucode/pangolin-newt.uc"

echo 'APK metadata and package contents look correct.'
