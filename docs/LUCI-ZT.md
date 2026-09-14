# luci-app-zt

`luci-app-zt` is an independent modern JavaScript LuCI interface for the
official OpenWrt `zerotier` package. It does not ship, replace or patch the
ZeroTier daemon.

The package name is intentionally not `luci-app-zerotier`. That canonical name
is already used by third-party projects and could eventually be used by an
official OpenWrt application. APK metadata declares a conflict with
`luci-app-zerotier` so two interfaces cannot concurrently manage the same UCI
configuration.

## Features

- Enable or disable ZeroTier, select its listening port and manage the
  `local_conf_path`, `config_path` and `copy_config_path` options supported by
  the OpenWrt 25.12 package.
- Add, edit, reorder and remove any number of `config network` sections with
  `allow_managed`, `allow_global`, `allow_default` and `allow_dns` controls.
- Show daemon state, online state, version, node ID, PID, uptime and the
  networks returned by `zerotier-cli -j listnetworks`.
- Start, stop and restart the official `/etc/init.d/zerotier` service.
- Show the latest 50 ZeroTier log lines.
- Refresh signed APK indexes and independently upgrade `zerotier` from the
  configured OpenWrt feed or `luci-app-zt` from this repository.

## Secret handling

The ZeroTier identity secret remains in `/etc/config/zerotier` and is preserved
when the GUI saves other settings. The browser has no direct UCI ACL for the
`zerotier` configuration. A sanitizing RPC returns only the supported public
settings and the boolean fact that an identity secret exists.

The RPC accepts a bounded schema, validates every network ID and option, and
never interpolates submitted values into shell commands. Logs are redacted
against the local identity secret before they are returned to LuCI.

## Package updates

Networked APK commands cannot run inside rpcd's restricted process. LuCI
therefore writes only one of three allowlisted requests (`check`,
`upgrade_zerotier`, `upgrade_luci`) and launches an on-demand procd worker. The
worker uses fixed package names and an atomic lock. Its `boot()` function is a
no-op, so package transactions never run automatically during router startup.

Upgrading `zerotier` restarts the daemon only when it was running before the
upgrade. Upgrading `luci-app-zt` does not restart ZeroTier.

## Installation

Once the signed repository documented in the main README is configured:

```sh
apk update
apk add luci-app-zt
```

Open **Services → ZeroTier**. Existing `/etc/config/zerotier` settings and the
identity secret are retained.

## Compatibility

The first release targets the OpenWrt 25.12.5 UCI schema introduced for
ZeroTier 1.14.1 and used by the official `zerotier` 1.16.0-r1 package. The LuCI
package is architecture-independent, while its dependency is resolved from the
official OpenWrt repository for the device architecture.
