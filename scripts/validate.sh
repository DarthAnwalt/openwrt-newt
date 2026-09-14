#!/usr/bin/env bash
# SPDX-License-Identifier: MIT

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

for script in \
	package/pangolin-newt/files/etc/init.d/newt \
	package/pangolin-newt/files/usr/libexec/newt-run \
	package/pangolin-newt/files/usr/libexec/newt-migrate \
	luci-app-pangolin-newt/root/etc/init.d/pangolin-newt-update \
	luci-app-pangolin-newt/root/usr/libexec/pangolin-newt-update \
	luci-app-zt/root/etc/init.d/luci-app-zt-update \
	luci-app-zt/root/usr/libexec/luci-app-zt-update; do
	sh -n "$script"
done

for script in scripts/*.sh; do
	bash -n "$script"
done

sh -n scripts/install.sh
grep -q "^PUBLIC_KEY_SHA256='[0-9a-f]\\{64\\}'$" scripts/install.sh
grep -q "^SUPPORTED_ARCH='aarch64_cortex-a53'$" scripts/install.sh
if grep -q -- '--allow-untrusted' scripts/install.sh; then
	echo 'The installer must never bypass APK signature verification.' >&2
	exit 1
fi
grep -Fq "jsonfilter -e '@[*].name'" scripts/install.sh
grep -Fq "grep -Fxq 'pangolin-newt'" scripts/install.sh

node --check luci-app-pangolin-newt/htdocs/luci-static/resources/view/pangolin-newt/overview.js
node --check luci-app-zt/htdocs/luci-static/resources/view/zt/overview.js

grep -q "const APK_BIN = '/usr/bin/apk';" \
	luci-app-pangolin-newt/root/usr/share/rpcd/ucode/pangolin-newt.uc
grep -Fq "init_action(UPDATE_SERVICE, 'start')" \
	luci-app-pangolin-newt/root/usr/share/rpcd/ucode/pangolin-newt.uc
grep -Fq '/usr/bin/apk upgrade pangolin-newt luci-app-pangolin-newt' \
	luci-app-pangolin-newt/root/usr/libexec/pangolin-newt-update
if grep -Eq '\$\{APK_BIN\} (update|upgrade)' \
	luci-app-pangolin-newt/root/usr/share/rpcd/ucode/pangolin-newt.uc; then
	echo 'Networked APK commands must run through the dedicated procd service.' >&2
	exit 1
fi
if grep -Eq 'package_action.*request.*args.*command' \
	luci-app-pangolin-newt/root/usr/share/rpcd/ucode/pangolin-newt.uc; then
	echo 'Package RPC must not interpolate request arguments into commands.' >&2
	exit 1
fi

grep -Fq "return { 'luci.zt': methods };" \
	luci-app-zt/root/usr/share/rpcd/ucode/luci-app-zt.uc
grep -Fq "init_action(UPDATE_SERVICE, 'start')" \
	luci-app-zt/root/usr/share/rpcd/ucode/luci-app-zt.uc
grep -Fq '/usr/bin/apk upgrade zerotier' \
	luci-app-zt/root/usr/libexec/luci-app-zt-update
grep -Fq '/usr/bin/apk upgrade luci-app-zt' \
	luci-app-zt/root/usr/libexec/luci-app-zt-update
if grep -Eq '\$\{APK_BIN\} (update|upgrade)' \
	luci-app-zt/root/usr/share/rpcd/ucode/luci-app-zt.uc; then
	echo 'ZeroTier networked APK commands must run through the dedicated procd service.' >&2
	exit 1
fi
if grep -Eq 'package_action.*request.*args.*command' \
	luci-app-zt/root/usr/share/rpcd/ucode/luci-app-zt.uc; then
	echo 'ZeroTier package RPC must not interpolate request arguments into commands.' >&2
	exit 1
fi
if grep -Eq "identity\\.secret|global\\.secret|['\\\"]secret['\\\"][[:space:]]*:" \
	luci-app-zt/htdocs/luci-static/resources/view/zt/overview.js; then
	echo 'The ZeroTier identity secret must never be sent to the browser.' >&2
	exit 1
fi

for json_file in \
	luci-app-pangolin-newt/root/usr/share/luci/menu.d/luci-app-pangolin-newt.json \
	luci-app-pangolin-newt/root/usr/share/rpcd/acl.d/luci-app-pangolin-newt.json \
	luci-app-zt/root/usr/share/luci/menu.d/luci-app-zt.json \
	luci-app-zt/root/usr/share/rpcd/acl.d/luci-app-zt.json; do
	python3 -m json.tool "$json_file" >/dev/null
done

grep -q '^/etc/config/newt$' package/pangolin-newt/Makefile
grep -q '$(INSTALL_CONF).*etc/config/newt' package/pangolin-newt/Makefile
grep -q '^export CONFIG_FILE=/dev/null$' package/pangolin-newt/files/usr/libexec/newt-run
grep -q '^exec /usr/bin/newt$' package/pangolin-newt/files/usr/libexec/newt-run
grep -q 'NEWT_SYSTEM_SUBSTRATE=OPENWRT_PACKAGE' package/pangolin-newt/files/usr/libexec/newt-run
grep -Fq '/usr/libexec/newt-run' package/pangolin-newt/Makefile
grep -Fq 'newt.apk-new' package/pangolin-newt/Makefile

if grep -Eq '^set -[^[:space:]]*u' package/pangolin-newt/files/usr/libexec/newt-run; then
	echo 'newt-run must not enable nounset around OpenWrt shell helpers.' >&2
	exit 1
fi

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
grep -q "^PKG_VERSION:=$LUCI_ZT_VERSION$" luci-app-zt/Makefile
grep -q "^PKG_RELEASE:=$LUCI_ZT_RELEASE$" luci-app-zt/Makefile
grep -q '^  CONFLICTS:=luci-app-zerotier$' luci-app-zt/Makefile
grep -q '^  EXTRA_DEPENDS:=!luci-app-zerotier$' luci-app-zt/Makefile

if grep -q '"uci"' luci-app-zt/root/usr/share/rpcd/acl.d/luci-app-zt.json; then
	echo 'luci-app-zt must use its sanitizing RPC instead of exposing the ZeroTier UCI secret.' >&2
	exit 1
fi

echo 'Static validation passed.'
