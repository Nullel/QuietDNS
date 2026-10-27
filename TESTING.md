# QuietDNS acceptance checks

## Automated (no DNS changes)

Run `./scripts/test.sh`, then `./scripts/build.sh`. Both must succeed. Run `Install and Open.command`; it verifies the clean signed bundle and installs it in `~/Applications`. Verify it again with `codesign --verify --deep --strict "$HOME/Applications/QuietDNS.app"`. Run the helper with `--list` and `--status`; confirm normal-user enable is rejected without changing anything.

## Interactive live checks (administrator approval required)

Use a personal network and close work VPNs before testing. Don't run this on a managed/company network without its administrator's guidance.

1. Before enabling, note each selected service's DNS in System Settings. Include a service using automatic DNS and, if available, a test service with static DNS and search domains. `networksetup -getdnsservers "Wi-Fi"` reads explicit server settings; `scutil --dns` shows effective resolvers including DHCP/scoped resolvers.
2. Open QuietDNS. Check that it starts off and that no DNS changes happen simply by opening it.
3. Click enable, **cancel** the macOS administrator prompt, and confirm DNS is unchanged and status remains off.
4. Enable and approve. Confirm the recovery file exists, owned by root and not writable by others. The selected services must have the configured filtering IPs; unselected/VPN services must remain unchanged. Search domains must remain unchanged.
5. Open **Check DNS**. Check `scutil --dns` shows the intended nameservers on the active service. Test ordinary sites. Optionally use `dig @94.140.14.14 example.com +time=2 +tries=1` for provider reachability; this explicit query doesn't prove your apps use it.
6. Turn off and approve. Confirm the original explicit DNS/search settings return exactly, automatic DNS returns where appropriate, and the journal is gone. DHCP can provide different *effective* addresses later; restoring automatic means removing the explicit override, not pinning old DHCP addresses.
7. Enable again, quit with **Keep DNS and Quit**, reopen and confirm it still knows how to restore. Repeat after a restart if desired. Turn off afterward.
8. While enabled, deliberately change DNS on a selected test service in System Settings. After refresh, status should require recovery. Normal restore must refuse the conflict. Review the edit, then use **Restore saved DNS anyway…**; verify the original is restored.
9. Test a custom resolver only if you control or trust it and know it serves plain DNS. Turn off again after the test.
10. Test **Restore and Quit**, `Emergency Restore.command`, and uninstall only after off. No recovery file should be deleted by an uninstall shortcut.

## BlueStacks check

With QuietDNS enabled, fully restart BlueStacks. Inside its browser open `https://adguard.com/en/test.html` and inspect the DNS result. Test the particular game separately; ad behavior varies and rewarded ads may become unavailable. Turn QuietDNS off, restart BlueStacks and compare. Document the emulator/game versions and whether an Android Private DNS setting or VPN is active. A browser-only result must not be reported as system-wide emulator coverage.

## Failure cases covered by automated tests

Apply failure after persistent commit, rollback failure, backup-write failure, enabled-phase save failure, missing/renamed service, partial interrupted transitions, repeat restore, external-edit conflicts, invalid addresses and shell metacharacters, no eligible selection, symlink/writable state rejection and concurrent operation lock contention.

Automated fault injection covers the transaction logic; it does not simulate macOS authorization UI, hardware failure, MDM policies or a live emulator. Live authentication, a complete DNS switch on a real network, and emulator coverage must be checked separately before a stable release.
