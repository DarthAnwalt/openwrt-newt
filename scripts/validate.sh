#!/usr/bin/env bash
# SPDX-License-Identifier: MIT

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

for script in \
	package/pangolin-newt/files/etc/init.d/newt \
	package/pangolin-newt/files/usr/libexec/newt-run \
	package/pangolin-newt/files/usr/libexec/newt-migrate; do
	sh -n "$script"
done

for script in scripts/*.sh; do
	bash -n "$script"
done

node --check luci-app-pangolin-newt/htdocs/luci-static/resources/view/pangolin-newt/overview.js

for json_file in \
	luci-app-pangolin-newt/root/usr/share/luci/menu.d/luci-app-pangolin-newt.json \
	luci-app-pangolin-newt/root/usr/share/rpcd/acl.d/luci-app-pangolin-newt.json; do
	python3 -m json.tool "$json_file" >/dev/null
done

grep -q '^/etc/config/newt$' package/pangolin-newt/Makefile
grep -q '$(INSTALL_CONF).*etc/config/newt' package/pangolin-newt/Makefile
grep -q '^export CONFIG_FILE=/dev/null$' package/pangolin-newt/files/usr/libexec/newt-run
grep -q '^exec /usr/bin/newt$' package/pangolin-newt/files/usr/libexec/newt-run
grep -q 'NEWT_SYSTEM_SUBSTRATE=OPENWRT_PACKAGE' package/pangolin-newt/files/usr/libexec/newt-run

if grep -Eq 'procd_(set|append)_param (command|env).*secret' package/pangolin-newt/files/etc/init.d/newt; then
	echo 'Secret must not be placed in the procd command or environment.' >&2
	exit 1
fi

source versions.env
grep -q "^PKG_VERSION:=$NEWT_VERSION$" package/pangolin-newt/Makefile
grep -q "^PKG_RELEASE:=$NEWT_RELEASE$" package/pangolin-newt/Makefile
grep -q "^PKG_VERSION:=$NEWT_VERSION$" luci-app-pangolin-newt/Makefile
grep -q "^PKG_RELEASE:=$NEWT_RELEASE$" luci-app-pangolin-newt/Makefile
grep -q "^PKG_HASH:=$NEWT_SOURCE_SHA256$" package/pangolin-newt/Makefile

echo 'Static validation passed.'
