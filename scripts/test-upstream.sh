#!/usr/bin/env bash
# SPDX-License-Identifier: MIT

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
source "$repo_root/versions.env"
sdk_dir="$(cd "${1:?path to the completed SDK build is required}" && pwd)"
source_dir="$(find "$sdk_dir/build_dir" -maxdepth 3 -type d -name "newt-$NEWT_VERSION" -print -quit)"
go_bin="$sdk_dir/staging_dir/hostpkg/lib/go-${GO_TOOLCHAIN_VERSION%.*}/bin/go"
[[ -n "$source_dir" && -x "$go_bin" ]]

# Test the same patched source and compiler that produced the package, but
# compile test executables for the Linux host rather than the router.
unset GOOS GOARCH GOARM GOARM64 GOROOT
export GOTOOLCHAIN=local CGO_ENABLED=0
export GOCACHE="$sdk_dir/tmp/newt-test-cache"
cd "$source_dir"
"$go_bin" version
"$go_bin" version | grep -Fq "go$GO_TOOLCHAIN_VERSION "
"$go_bin" test -timeout 5m ./...

network_test="$(mktemp "$sdk_dir/tmp/newt-network-test.XXXXXX")"
trap 'rm -f "$network_test"' EXIT
"$go_bin" test -c -o "$network_test" ./network
# Only the isolated test executable runs with privilege in a fresh network
# namespace. It cannot change the build host's interfaces or routing table.
sudo env NETNS_TEST=1 unshare --net -- "$network_test" \
	-test.timeout=1m -test.run='^TestBypassReconcileNetns$' -test.v
