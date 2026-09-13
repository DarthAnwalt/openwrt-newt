# Release checklist

1. Review the upstream Newt release notes and license.
2. Update `PKG_VERSION`, `PKG_RELEASE` and `versions.env`.
3. Download the exact codeload tag archive and update `PKG_HASH`.
4. Confirm the upstream `go` directive is supported by the pinned OpenWrt
   packages feed.
5. Rebase and review downstream patches.
6. Run `./scripts/validate.sh`.
7. Let CI complete the pinned SDK build and APK smoke test.
8. Test installation, connection, reboot and package upgrade on the target
   router.
9. Verify that `/var/run/newt/healthy` tracks Pangolin connectivity and that
   no credential appears in `ps`, `ubus call service list`, LuCI status or
   `logread`.
10. Confirm `APK_SIGNING_KEY_B64` is configured and GitHub Pages uses GitHub
    Actions as its source.
11. Tag `v<upstream>-r<release>`. The release workflow signs and verifies the
    index, deploys Pages and creates a GitHub release.
12. On a clean router, import the published public key and prove
    `apk add pangolin-newt luci-app-pangolin-newt` succeeds without
    `--allow-untrusted`.
13. On a router with a manual install, prove `install.sh --migrate` moves the
    legacy init script out of `/etc/init.d`, retains the JSON and backup, starts
    exactly one process, and creates `/var/run/newt/healthy`.
14. In LuCI, refresh package indexes and verify that the asynchronous procd
    worker completes outside the rpcd sandbox and that only the two Newt
    packages are offered to the fixed-name upgrade action.

If only packaging changes, increment `PKG_RELEASE`. When Newt changes,
replace `PKG_VERSION` and normally reset `PKG_RELEASE` to 1.
