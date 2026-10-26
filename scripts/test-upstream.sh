#!/usr/bin/env bash
# SPDX-License-Identifier: MIT

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
source "$repo_root/versions.env"
sdk_dir="$(cd "${1:?path to the completed SDK build is required}" && pwd)"
go_bin="$sdk_dir/staging_dir/hostpkg/lib/go-${GO_TOOLCHAIN_VERSION%.*}/bin/go"
[[ -x "$go_bin" ]]
archive="$sdk_dir/dl/newt-$NEWT_VERSION.tar.gz"
echo "$NEWT_SOURCE_SHA256  $archive" | sha256sum -c -
test_root="$(mktemp -d "$sdk_dir/tmp/newt-upstream-tests.XXXXXX")"
trap 'rm -rf "$test_root"' EXIT
tar -xzf "$archive" -C "$test_root"
source_dir="$test_root/newt-$NEWT_VERSION"
test -f "$source_dir/go.mod"
for patch_file in "$repo_root"/package/pangolin-newt/patches/*.patch; do
	patch --batch --forward -p1 -d "$source_dir" --input "$patch_file"
done

# SDK packaging may clean or relocate the build tree. Test a fresh copy of
# the identical verified archive/patches with the package's own compiler.
# Compile test executables for the Linux host rather than the router.
unset GOOS GOARCH GOARM GOARM64 GOROOT
export GOENV=off GOWORK=off GO111MODULE=on GOTOOLCHAIN=local CGO_ENABLED=0
export GOCACHE="$sdk_dir/tmp/newt-test-cache"
cd "$source_dir"
"$go_bin" version
"$go_bin" version | grep -Fq "go$GO_TOOLCHAIN_VERSION "
"$go_bin" test -timeout 5m ./...

network_test="$test_root/network.test"
"$go_bin" test -c -o "$network_test" ./network
# Only the isolated test executable runs with privilege in a fresh network
# namespace. It cannot change the build host's interfaces or routing table.
sudo env NETNS_TEST=1 unshare --net -- "$network_test" \
	-test.timeout=1m -test.run='^TestBypassReconcileNetns$' -test.v
