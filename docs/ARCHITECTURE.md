# Architecture notes

## Package boundary

`pangolin-newt` owns the binary, service, UCI file, launcher and migration
helper. `luci-app-pangolin-newt` depends on it and owns the LuCI UI/RPC files
plus a one-shot procd worker for signed APK refreshes and fixed-name upgrades.
The deliberately namespaced APK names leave `newt` and
`luci-app-newt` available for a future upstream or official OpenWrt package;
runtime paths retain the conventional `newt` name.

The procd command is `/usr/libexec/newt-run`, with no credentials in argv.
The launcher reads UCI, waits for a default route, exports Newt's supported
environment variables and replaces itself with `/usr/bin/newt`.

Connectivity is based on Newt's `HEALTH_FILE` feature. Newt writes the file
after a successful tunnel ping and removes it when the tunnel is lost. This is
more stable than parsing log wording.

The RPC process only writes an allowlisted `check` or `upgrade` request and
asks procd to start the worker. The worker runs outside rpcd's syscall sandbox,
uses an atomic directory lock, and invokes only fixed `/usr/bin/apk` commands.
Its state and bounded output are exposed back through the read-only status RPC.

`luci-app-zt` is a separate architecture-independent package. It depends on the
official OpenWrt `zerotier` package and owns no daemon files. Its JSONMap is fed
by a sanitizing RPC instead of direct UCI ACL access, so the identity secret is
never returned to the browser. The RPC preserves that secret while replacing
only validated global options and network sections.

The ZeroTier update worker has separate fixed actions for `zerotier` and
`luci-app-zt`. This permits the official daemon and our GUI to follow their own
package versions and repositories while sharing one signed index refresh.

OpenWrt 25.12 records a package's `CONFLICTS` in its intermediate metadata but
does not pass that field to `apk mkpkg`. The pinned build therefore applies the
small audited patch in `patches/openwrt-25.12-apk-conflicts.patch`, translating
each conflict to APK v3's negated dependency form. The APK smoke test verifies
that `!luci-app-zerotier` is present in the finished package. Remove this patch
only after the pinned OpenWrt SDK emits conflicts itself and the smoke test has
confirmed the replacement behavior.

## Source build decision

Newt 1.19.0 declares Go 1.26.0. The packages feed commit shipped with OpenWrt
25.12.5 provides Go 1.26 and knows the Cortex-A53 `GOARM64=v8.0` baseline.
The compiler recipe is backported to **Go 1.26.10** by changing only its point
release and official source checksum; the same backport is applied to the
25.12.6 profile (originally Go 1.26.9). This prevents shipping older embedded
TLS/X.509 standard-library code just to retain an older SDK baseline. The
patches and checksum are versioned in this repository, and CI checks the
compiler actually used by the tests.
The upstream build already sets `CGO_ENABLED=0`, so the result is portable
across musl targets of the same architecture.

Release builds retain the 25.12.5 baseline in `versions.env`. The separately
pinned `sdk/25.12.6.env` profile is selected with `SDK_PROFILE=25.12.6` for
compatibility CI. Both builds verify that the SDK's checked-out packages and
LuCI feed commits match the manifest. CI executes the extracted ARM64 binary
with QEMU, tests the patched upstream source and runs the routing regression
inside an isolated Linux network namespace. This does not claim a full
hardware/GUI/tunnel test on a 25.12.6 firmware installation.

Newt 1.19's client identity headers are populated from Pangolin's WebSocket
configuration; no new local CLI/UCI switch exists. The launcher and LuCI form
therefore retain their existing options. The self-update guard and AGPL
source publication remain unchanged.

The source build is preferred over repackaging the upstream binary because it
uses OpenWrt's pinned toolchain, carries the exact source/license into the
build, and makes architecture matrix expansion mechanical.

## Adding an architecture

Add a matrix row with a concrete OpenWrt SDK URL and SHA256. Also add the SDK
metadata to a version manifest (or split `versions.env` into per-target
records when the second target is introduced). Build and hardware-test the
target before publishing.

Do not point a release job at snapshots or a moving `latest` URL.

## Repository trust

OpenWrt 25.12 consumes an APK v3 `packages.adb`. The workflow signs that
index with an EC P-256 private key. The device trusts the corresponding public
PEM in `/etc/apk/keys`, and the signed index authenticates package content
hashes.

The private key exists only in an offline backup and GitHub Actions secret. It
is materialized under `$RUNNER_TEMP`, mode 0600, for the signing step and
removed immediately afterward.
