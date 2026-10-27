# QuietDNS

A small macOS menu-bar app for switching ad-blocking DNS on and off. Turn it on to use AdGuard DNS or a custom resolver. Turn it off to restore the DNS settings that were there before.

QuietDNS works with selected Wi-Fi and Ethernet services. It saves the full original DNS configuration before making a change, including automatic DNS and search domains.

## Install

Requires **macOS 14 or later**. The preview download is built for **Apple Silicon**.

1. Download **QuietDNS-Mac.zip** from [Releases](https://github.com/Nullel/QuietDNS/releases).
2. Unzip it and double-click **Install and Open.command**. The installer verifies the app and puts it in `~/Applications`.
3. Click the shield in the menu bar, then **Turn On Ad Blocking**. Approve the macOS administrator prompt.
4. Restart any app that cached DNS, including BlueStacks.

To turn it off, click **Turn Off & Restore DNS**. macOS may ask for administrator approval each time you change DNS. QuietDNS never receives or stores your password.

The preview is locally signed, **not Apple-notarized**. If macOS blocks a downloaded copy, build it from source on that Mac. Do not disable Gatekeeper.

## Build from source

Install Xcode or Apple's Command Line Tools with Swift 6 or newer. There are no external dependencies.

```sh
git clone https://github.com/Nullel/QuietDNS.git
cd QuietDNS
./scripts/test.sh
./scripts/build.sh
"./Install and Open.command"
```

Or double-click **Build QuietDNS.command** to build, install, and open the app. Build output goes into `work/build`; the packaged app is written to `dist/QuietDNS.app.zip`. `QUIETDNS_BUILD_ROOT` can override the build directory.

The build targets the architecture of the Mac running it. The scripts use SwiftPM's native build engine for compatibility with the standalone Command Line Tools test setup. Swift 6.4 marks that engine deprecated, so a future toolchain may need an updated build command.

## What it blocks

QuietDNS can block requests to many advertising and tracking domains in browsers and apps that use the configured system resolver. It does not inspect page content or count blocked ads.

DNS filtering has limits:

- YouTube, Twitch, and other ads served from the same domain as the content can remain. [Why DNS cannot block these](https://adguard-dns.io/kb/adguard-home/faq/).
- VPNs, iCloud Private Relay, browser Secure DNS, managed profiles, and apps using their own resolver can bypass system DNS.
- Existing connections and cached ads may remain until an app is restarted.
- **On** means the filtering DNS settings are configured. It does not verify that every app uses them or that the resolver is reachable.

For browser ads, a content blocker can help: [uBlock Origin for Firefox](https://github.com/gorhill/uBlock), [uBlock Origin Lite for Chromium](https://github.com/uBlockOrigin/uBOL-home), or [AdGuard Mini for Safari](https://github.com/AdguardTeam/AdGuardMiniForMac).

## DNS providers and privacy

AdGuard DNS is the default. Its public filtering servers are:

```text
94.140.14.14
94.140.15.15
2a10:50c0::ad1:ff
2a10:50c0::ad2:ff
```

See [AdGuard's provider information](https://adguard-dns.io/en/public-dns.html) and [privacy policy](https://adguard-dns.io/en/privacy.html).

While QuietDNS is off, choose **Custom IP addresses** to use a trusted filtering provider or a local resolver such as AdGuard Home or Pi-hole. Enter 1–8 IPv4 or IPv6 addresses separated by commas or whitespace. They must accept **plain DNS on port 53**; DoH/DoT-only endpoints will not work. Localhost addresses only work if a resolver is already running there. Do not mix filtered and unfiltered servers, since macOS can use any listed server.

This version does not encrypt DNS. Domain lookups go to the selected provider and can also be visible to the network operator. There are no accounts, analytics, or query-history logs. QuietDNS does not edit the hosts file, install certificates, or intercept HTTPS.

To allow a blocked site, turn filtering off temporarily or manage an allowlist on a custom resolver. Internal company or school sites may require that network's DNS. New adapters are not changed automatically: turn filtering off, select the new service under **Networks**, then enable it again. VPN and virtual interfaces are excluded.

## Restore and uninstall

Turn QuietDNS off before removing it. Once it reports off, quit and move the app to Trash. There is no daemon, login item, network extension, or profile to remove.

If you choose **Keep DNS and Quit**, the DNS settings stay in effect after quitting or restarting the Mac. Reopen QuietDNS to restore them later.

If the app will not open, double-click **Emergency Restore.command** from the downloaded package, or run:

```sh
sudo "$HOME/Applications/QuietDNS.app/Contents/MacOS/quietdns-helper" --restore
```

Recovery works offline. If the installed app is missing, the emergency script can use the packaged helper. A source checkout needs to be built first. Keep `/Library/Application Support/QuietDNS/recovery.plist` until recovery succeeds.

If another app changed DNS after QuietDNS was enabled, normal restore stops to protect those edits. Review **Check DNS** and the service's DNS settings in System Settings. Choose **Restore saved DNS anyway…** only if you want the saved original settings to replace those newer edits. The command-line equivalent is `--restore-force`. Removed services need manual recovery; force does not recreate them or discard their backups.

If internet access breaks, turn QuietDNS off. Disable it before signing in to a hotel or other captive-portal network. The helper's `--backup` command prints the saved original settings for recovery; do not blindly clear a static or corporate resolver.

After a successful restore, the recovery file is deleted. An empty operation lock remains to prevent lock races. To remove that inactive data too, first confirm filtering is off and all QuietDNS processes are closed:

```sh
defaults delete local.quietdns.menubar
sudo /bin/rm -f "/Library/Application Support/QuietDNS/operation.lock"
sudo /bin/rmdir "/Library/Application Support/QuietDNS"
```

`rmdir` refuses to remove a nonempty folder. Do not delete a remaining recovery file to make uninstall finish. The installer preserves older builds as `QuietDNS.previous.*.app`; these can also be moved to Trash after restoring DNS.

## Development

Run `./scripts/test.sh` for the automated suite. Its 23 tests use fake network stores and isolated temporary journals; they do not change live DNS or request administrator access. See [TESTING.md](TESTING.md) for manual checks, including authentication, live restore, and BlueStacks.

The normal-user app starts a short-lived administrator helper for DNS changes. The helper uses SystemConfiguration, locks preferences, and writes an atomic recovery journal before changing any service. It keys backups by stable service IDs and preserves the entire DNS dictionary, including whether it was absent. Failed enables attempt rollback; interrupted operations and failed restores retain the journal for retry. Unrelated DNS edits require an explicit force-restore choice.

The root-owned journal is readable by local users, like the underlying network settings. It contains service names, DNS settings, and timestamps, not browsing history. Writable recovery files, symlinks, damaged data, and unsupported journal versions are rejected.

Read-only diagnostics:

```sh
"$HOME/Applications/QuietDNS.app/Contents/MacOS/quietdns-helper" --status
"$HOME/Applications/QuietDNS.app/Contents/MacOS/quietdns-helper" --list
"$HOME/Applications/QuietDNS.app/Contents/MacOS/quietdns-helper" --backup
scutil --dns
```
