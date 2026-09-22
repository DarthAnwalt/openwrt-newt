#!/usr/bin/env bash
# SPDX-License-Identifier: MIT

set -euo pipefail
umask 022

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
source "$repo_root/versions.env"

build_root="${BUILD_ROOT:-$repo_root/work}"
output_dir="${OUTPUT_DIR:-$repo_root/dist/aarch64_cortex-a53}"
sdk_archive="$build_root/$SDK_FILENAME"
sdk_parent="$build_root/sdk"

mkdir -p "$build_root" "$output_dir"

if [[ ! -f "$sdk_archive" ]] || ! echo "$SDK_SHA256  $sdk_archive" | sha256sum -c -; then
	curl --fail --location --retry 3 --output "$sdk_archive.part" "$SDK_URL"
	echo "$SDK_SHA256  $sdk_archive.part" | sha256sum -c -
	mv "$sdk_archive.part" "$sdk_archive"
fi

rm -rf "$sdk_parent"
mkdir -p "$sdk_parent"
tar --zstd -xf "$sdk_archive" -C "$sdk_parent"
sdk_dir="$(find "$sdk_parent" -mindepth 1 -maxdepth 1 -type d -name 'openwrt-sdk-*' -print -quit)"
[[ -n "$sdk_dir" ]]

# OpenWrt 25.12 records Package/*/CONFLICTS in its intermediate metadata but
# omits it from `apk mkpkg`. APK v3 represents conflicts as negated runtime
# dependencies. Apply a small, auditable SDK patch until OpenWrt emits them.
patch --batch --forward --strip=1 --directory "$sdk_dir" \
	--input "$repo_root/patches/openwrt-25.12-apk-conflicts.patch"

(
	cd "$sdk_dir"
	# Keep the SDK's checksum-pinned feeds.conf.default. In particular, its
	# --root=package base feed provides build dependencies such as ucode and Lua.
	# Replacing this file with only packages/luci makes lucihttp fail to compile.
	./scripts/feeds update base packages luci
	./scripts/feeds install -p base \
		ca-certificates jsonfilter libjson-c libmd libnl-tiny libubox \
		lua rpcd ubus uci ucode
	./scripts/feeds install -p packages cgi-io golang zerotier
	./scripts/feeds install -p luci \
		csstidy luci-base lucihttp rpcd-mod-luci ucode-mod-html

	cp -R "$repo_root/package/pangolin-newt" package/pangolin-newt
	cp -R "$repo_root/luci-app-pangolin-newt" package/luci-app-pangolin-newt
	cp -R "$repo_root/luci-app-zt" package/luci-app-zt

	make defconfig
	make package/pangolin-newt/download V=s
	make -j"${BUILD_JOBS:-2}" package/pangolin-newt/compile V=s
	make -j"${BUILD_JOBS:-2}" package/luci-app-pangolin-newt/compile V=s
	make -j"${BUILD_JOBS:-2}" package/luci-app-zt/compile V=s
)

rm -f "$output_dir"/*.apk
find "$sdk_dir/bin" -type f \( -name 'pangolin-newt-*.apk' -o -name 'luci-app-pangolin-newt-*.apk' -o -name 'luci-app-zt-*.apk' \) \
	-exec cp -f {} "$output_dir/" \;

newt_count="$(find "$output_dir" -maxdepth 1 -type f -name 'pangolin-newt-*.apk' | wc -l | tr -d ' ')"
luci_count="$(find "$output_dir" -maxdepth 1 -type f -name 'luci-app-pangolin-newt-*.apk' | wc -l | tr -d ' ')"
luci_zt_count="$(find "$output_dir" -maxdepth 1 -type f -name 'luci-app-zt-*.apk' | wc -l | tr -d ' ')"
[[ "$newt_count" == 1 && "$luci_count" == 1 && "$luci_zt_count" == 1 ]]

"$repo_root/scripts/smoke-apk.sh" "$sdk_dir/staging_dir/host/bin/apk" "$output_dir"

printf '%s\n' "$sdk_dir" >"$build_root/sdk-path"
echo "Built packages are in $output_dir"
