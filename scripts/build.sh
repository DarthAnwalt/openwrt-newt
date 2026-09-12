#!/usr/bin/env bash
# SPDX-License-Identifier: MIT

set -euo pipefail

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

(
	cd "$sdk_dir"
	# Keep the SDK's checksum-pinned feeds.conf.default. In particular, its
	# --root=package base feed provides build dependencies such as ucode and Lua.
	# Replacing this file with only packages/luci makes lucihttp fail to compile.
	./scripts/feeds update base packages luci
	./scripts/feeds install -a -p base
	./scripts/feeds install -p packages golang
	./scripts/feeds install -a -p luci

	cp -R "$repo_root/package/pangolin-newt" package/pangolin-newt
	cp -R "$repo_root/luci-app-pangolin-newt" package/luci-app-pangolin-newt

	make defconfig
	make package/pangolin-newt/download V=s
	make -j"${BUILD_JOBS:-2}" package/pangolin-newt/compile V=s
	make -j"${BUILD_JOBS:-2}" package/luci-app-pangolin-newt/compile V=s
)

rm -f "$output_dir"/*.apk
find "$sdk_dir/bin" -type f \( -name 'pangolin-newt-*.apk' -o -name 'luci-app-pangolin-newt-*.apk' \) \
	-exec cp -f {} "$output_dir/" \;

newt_count="$(find "$output_dir" -maxdepth 1 -type f -name 'pangolin-newt-*.apk' | wc -l | tr -d ' ')"
luci_count="$(find "$output_dir" -maxdepth 1 -type f -name 'luci-app-pangolin-newt-*.apk' | wc -l | tr -d ' ')"
[[ "$newt_count" == 1 && "$luci_count" == 1 ]]

"$repo_root/scripts/smoke-apk.sh" "$sdk_dir/staging_dir/host/bin/apk" "$output_dir"

printf '%s\n' "$sdk_dir" >"$build_root/sdk-path"
echo "Built packages are in $output_dir"
