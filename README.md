# openwrt-newt

Native OpenWrt packages for [Fossorial Newt](https://github.com/fosrl/newt),
the Pangolin tunnel client:

- `pangolin-newt`: a source-built Newt binary, UCI configuration, procd service and
  migration helper;
- `luci-app-pangolin-newt`: a modern JavaScript LuCI page under **Services → Newt**;
- a signed APK v3 repository published by GitHub Actions and GitHub Pages.

The initial target is OpenWrt 25.12.5 on `mediatek/filogic`
(`aarch64_cortex-a53`). The same build supports both the GL.iNet Brume 2 and
Huasifei WH3000 Pro; no device-specific package is required. The CI matrix is
ready for additional SDK targets.

## Current versions

| Component | Version |
|---|---|
| OpenWrt SDK | 25.12.5, mediatek/filogic |
| Package architecture | aarch64_cortex-a53 |
| Newt | 1.15.0-r2 |
| Package manager | OpenWrt APK v3 |

Exact SDK, feed commits and checksums are recorded in
[`versions.env`](versions.env). Newt is built from the exact upstream tag
using the OpenWrt Go toolchain. OpenWrt 25.12.5's pinned packages feed provides
Go 1.26; Newt 1.15.0 requires Go 1.25.

## One-line install

On a supported OpenWrt router, run as `root`:

```sh
uclient-fetch -qO /tmp/install-openwrt-newt.sh https://DarthAnwalt.github.io/openwrt-newt/install.sh && sh /tmp/install-openwrt-newt.sh
```

The installer checks OpenWrt 25.12 and `aarch64_cortex-a53`, downloads the
repository public key, verifies its pinned SHA-256 fingerprint, adds the feed
only if it is absent, and installs both packages without
`--allow-untrusted`. It is safe to run again when updating or repairing the
installation. It never asks for or handles the Newt ID or secret.

For additional assurance, download and inspect
[`scripts/install.sh`](scripts/install.sh) before running it. The initial HTTPS
download of the installer remains a trust-on-first-use step; the embedded key
fingerprint protects against an accidental or substituted repository key after
the script itself has been obtained.

## Manual install from the signed repository

Confirm the router reports the supported package architecture first:

```sh
apk --print-arch
```

The expected result for both Brume 2 and WH3000 Pro is
`aarch64_cortex-a53`. If an OEM hardware revision reports anything else, do
not use this repository until that architecture has its own CI build.

1. Import the repository public key:

   ```sh
   uclient-fetch -O /etc/apk/keys/openwrt-newt.pem \
     https://DarthAnwalt.github.io/openwrt-newt/repository/openwrt-newt.pem
   chmod 0644 /etc/apk/keys/openwrt-newt.pem
   ```

2. Add the architecture-specific repository:

   ```sh
   repo='https://DarthAnwalt.github.io/openwrt-newt/repository/25.12/aarch64_cortex-a53/packages.adb'
   grep -Fqx "$repo" /etc/apk/repositories.d/customfeeds.list 2>/dev/null || \
     echo "$repo" >> /etc/apk/repositories.d/customfeeds.list
   ```

3. Install normally, without `--allow-untrusted`:

   ```sh
   apk update
   apk add pangolin-newt luci-app-pangolin-newt
   ```

The HTTPS download of the public key is the trust-on-first-use step. For a
stronger bootstrap, compare the downloaded key with the copy attached to the
same GitHub release through a second trusted channel.

## Configure

In LuCI, open **Services → Newt**, enable the service, enter the Pangolin
endpoint, Newt ID and secret, select a log level, then choose **Save & Apply**.
The status panel reports:

- procd process state;
- tunnel connectivity using Newt's own health file;
- Newt version, PID and uptime;
- the latest 50 `logread` lines;
- Start, Stop and Restart controls.

The upstream server version is intentionally not shown: Newt 1.15.0 does not
expose a stable local API for it, and parsing log messages would be brittle.

Equivalent UCI setup:

```sh
uci set newt.main.enabled='1'
uci set newt.main.endpoint='https://pangolin.example.com'
uci set newt.main.id='YOUR_NEWT_ID'
uci set newt.main.secret='YOUR_NEWT_SECRET'
uci set newt.main.log_level='INFO'
uci commit newt
chmod 0600 /etc/config/newt
/etc/init.d/newt enable
/etc/init.d/newt restart
```

Optional launcher settings already supported for future UI expansion are
`dns`, `mtu`, `ping_interval`, `ping_timeout` and
`wait_for_network`.

## Migrate a manual installation

The helper reads
`/root/.config/newt-client/config.json`, never prints credentials, and never
modifies or removes the source file:

```sh
/usr/libexec/newt-migrate --check
/usr/libexec/newt-migrate --apply
```

It refuses to overwrite an already configured UCI section. Review the result,
verify that the site is online, and only then remove the legacy JSON:

```sh
uci show newt | sed 's/\.secret=.*/.secret=[redacted]/'
/etc/init.d/newt status
test -e /var/run/newt/healthy && echo connected
```

If a manually created `/etc/init.d/newt` exists, back it up before installing
the package. APK will otherwise treat the path as package-owned. The package's
`/usr/bin/newt` replaces the manual binary.

## Updates

Upgrade only these packages:

```sh
apk update
apk upgrade pangolin-newt luci-app-pangolin-newt
```

Do not use an unqualified `apk upgrade` on OpenWrt. Firmware packages are a
coherent set and should normally be updated with sysupgrade.

Newt's built-in binary self-update is disabled by a small downstream patch.
This prevents an upstream update from replacing a file owned by APK.

## Sysupgrade behavior

`/etc/config/newt` is declared as a conffile and installed mode `0600`.
Normal package upgrades preserve local changes. A regular sysupgrade preserves
configuration under `/etc` according to OpenWrt backup rules.

Attended Sysupgrade can restore user-installed packages only when its build
service can reach a compatible repository and trust its key. Rebuild and
publish these packages for each new OpenWrt release series before upgrading;
do not assume a 25.12 repository is ABI-compatible with a later series. Keep an
independent backup of `/etc/config/newt` and the repository key.

## Uninstall

```sh
/etc/init.d/newt stop
apk del luci-app-pangolin-newt pangolin-newt
```

Back up `/etc/config/newt` first if credentials may be needed again. Confirm
whether the local APK version retained or removed the modified conffile after
uninstall.

## Troubleshooting

```sh
logread -e newt
/etc/init.d/newt status
pgrep -af newt
/usr/bin/newt --version
test -e /var/run/newt/healthy && echo connected || echo disconnected
```

If Newt remains in “waiting for a default network route”, check
`ip route show default` and `ip -6 route show default`. Set
`newt.main.wait_for_network='0'` only for a local endpoint reachable without
a default route.

## Build locally

The supported build host is x86_64 Linux:

```sh
./scripts/validate.sh
./scripts/build.sh
```

The build script downloads the exact 25.12.5 SDK, verifies its SHA256, pins the
packages and LuCI feed commits, builds both APKs and checks their metadata and
contents with the SDK's APK tool.

macOS can run static validation, but the official SDK archive contains Linux
x86_64 host tools. Use a Linux VM or GitHub Actions for the full build.

## Signing and publishing

Generate the APK v3 P-256 signing key once on a trusted workstation:

```sh
./scripts/generate-signing-key.sh /secure/offline/openwrt-newt
```

Keep `private-key.pem` offline and never commit it. Store its base64 encoding
in the repository secret `APK_SIGNING_KEY_B64`. The release workflow derives
the public key, creates and verifies a signed `packages.adb`, publishes the
repository through GitHub Pages, and attaches the repository files to tagged
GitHub releases. It also publishes the exact upstream Newt source archive and
a source snapshot of this packaging repository under `repository/source/`.

Enable GitHub Pages with **Source: GitHub Actions**, add the secret, then push a
tag:

```sh
git tag v1.15.0-r2
git push origin v1.15.0-r2
```

The weekly upstream watcher opens an issue when a newer Newt release appears.
It never bumps or publishes packages automatically.

See [RELEASING.md](docs/RELEASING.md) for the complete release checklist.

## Security design

- Credentials are stored in root-readable UCI configuration.
- The launcher passes credentials through the process environment, not argv or
  procd's public command array.
- The legacy upstream JSON path is disabled for package-managed runs.
- LuCI RPC methods never return the secret; log output is additionally
  redacted before it reaches the browser.
- Service actions use a strict allowlist.
- UI status and logs are rendered as text nodes, not HTML.
- Newt waits for a default route and is supervised by procd with respawn.

Administrators with root shell access can still inspect the process
environment and the UCI file; that is inherent to running a credentialed
system service as root.

## Licensing

The original OpenWrt integration and LuCI code in this repository is MIT
licensed. The downstream patch under `package/pangolin-newt/patches/` modifies Newt
and is distributed under AGPL-3.0-only.

Newt itself is upstream software dual-licensed under AGPL-3.0 and the
Fossorial commercial license. This package redistributes the AGPL build. The
exact upstream source tag, downstream patch and complete build recipe are
published alongside each release, and the upstream AGPL license is installed
at `/usr/share/licenses/newt/LICENSE`.

Before distributing modified Newt builds, review the AGPL network-source and
corresponding-source requirements. This section documents the project design;
it is not legal advice.

## Primary references

- [OpenWrt APK package manager](https://openwrt.org/docs/guide-user/additional-software/apk)
- [OpenWrt package build documentation](https://openwrt.org/docs/guide-developer/packages)
- [OpenWrt 25.12 LuCI example application](https://github.com/openwrt/luci/tree/openwrt-25.12/applications/luci-app-example)
- [OpenWrt APK index implementation](https://github.com/openwrt/openwrt/blob/openwrt-25.12/package/Makefile)
- [Newt 1.15.0 source and license](https://github.com/fosrl/newt/tree/1.15.0)
