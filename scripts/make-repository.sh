#!/usr/bin/env bash
# SPDX-License-Identifier: MIT

set -euo pipefail

apk_bin="${1:?path to the SDK apk tool is required}"
private_key="${2:?private signing key is required}"
repository_dir="${3:?repository output directory is required}"
public_key_output="${4:?public key output path is required}"
shift 4

[[ "$#" -gt 0 ]]
[[ -x "$apk_bin" ]]
[[ -s "$private_key" ]]

mkdir -p "$repository_dir" "$(dirname "$public_key_output")"
chmod 0600 "$private_key"
openssl ec -in "$private_key" -check -noout
openssl ec -in "$private_key" -pubout -out "$public_key_output"

for package in "$@"; do
	cp -f "$package" "$repository_dir/"
done

(
	cd "$repository_dir"
	"$apk_bin" mkndx \
		--allow-untrusted \
		--sign "$private_key" \
		--output packages.adb \
		 ./*.apk
	"$apk_bin" adbdump --format json packages.adb >index.json
	sha256sum ./*.apk packages.adb >SHA256SUMS
)

verify_keys="$(mktemp -d)"
trap 'rm -rf "$verify_keys"' EXIT
cp "$public_key_output" "$verify_keys/"
"$apk_bin" verify --keys-dir "$verify_keys" "$repository_dir/packages.adb"

echo "Signed repository created in $repository_dir"

