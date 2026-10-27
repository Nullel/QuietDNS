import AppKit
import SwiftUI
import QuietDNSCore

@MainActor
final class AppModel: ObservableObject {
    @Published var state = "loading"
    @Published var detail = "Reading network settings…"
    @Published var provider = UserDefaults.standard.string(forKey: "provider") ?? "AdGuard DNS"
    @Published var custom = UserDefaults.standard.string(forKey: "customDNS") ?? ""
    @Published var services = [NetworkService]()
    @Published var selected = Set<String>()
    @Published var busy = false
    @Published var error: String?
    @Published var savedProvider: String?
    @Published var savedServices = [String]()
    @Published var forceRestore = false
    var didLoadSelection = false
    var changed: (() -> Void)?
    var hasBackup: Bool { state != "off" && state != "loading" }
    var helper: String { Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/quietdns-helper").path }

    func refresh() {
        guard !busy else { return }
        do {
            let network = try SystemNetworkStore()
            let status = try DNSEngine(network: network, journal: FileJournalStore()).status()
            services = try network.services().filter { $0.eligible && $0.enabled }
            if !didLoadSelection {
                if let stored = UserDefaults.standard.array(forKey: "services") as? [String] {
                    selected = Set(stored)
                } else { selected = Set(services.map(\.id)) }
                didLoadSelection = true
            }
            state = status.state; detail = status.detail; savedProvider = status.provider; savedServices = status.services
        } catch {
            state = "unknown"; detail = error.localizedDescription
        }
        changed?()
    }

    func toggle() {
        if hasBackup { operate(["--restore"]) }
        else {
            do {
                let ips = provider == "AdGuard DNS" ? DNSProvider.adGuard : try DNSProvider.parse(custom)
                let currentIDs = Set(services.map(\.id))
                let ids = selected.intersection(currentIDs).sorted()
                guard !ids.isEmpty else { throw QuietError("Select at least one Wi-Fi or Ethernet service under Networks.") }
                UserDefaults.standard.set(provider, forKey: "provider")
                UserDefaults.standard.set(custom, forKey: "customDNS")
                UserDefaults.standard.set(ids, forKey: "services")
                operate(["--enable", provider, ips.joined(separator: ",")] + ids)
            } catch { self.error = error.localizedDescription }
        }
    }

    func operate(_ arguments: [String], quitAfter: Bool = false) {
        guard !busy else { return }
        guard FileManager.default.isExecutableFile(atPath: helper) else {
            error = "The DNS helper is missing. Run Build QuietDNS.command to rebuild and install the app. Keep any recovery file."; return
        }
        busy = true; changed?()
        let path = helper
        Task {
            let result = await Task.detached { () -> Result<CommandResult, Error> in
                Result { try CommandRunner.administrator(helper: path, arguments: arguments) }
            }.value
            busy = false
            switch result {
            case .success(let result) where result.code == 0:
                refresh()
                if quitAfter { NSApplication.shared.terminate(nil) }
            case .success(let result):
                refresh()
                if result.output.contains("(-128)") || result.output.lowercased().contains("user canceled") {
                    error = "Administrator approval was cancelled. No new DNS operation was started."
                } else { error = result.output.trimmingCharacters(in: .whitespacesAndNewlines) }
            case .failure(let failure): refresh(); error = failure.localizedDescription
            }
            changed?()
        }
    }

    func quit() {
        guard !busy else { return }
        refresh()
        if !hasBackup { NSApplication.shared.terminate(nil); return }
        NSApplication.shared.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Restore DNS before quitting?"
        alert.informativeText = "DNS settings stay in effect after quitting or restarting. You can restore them now, or keep filtering and reopen QuietDNS later."
        alert.addButton(withTitle: "Restore and Quit")
        alert.addButton(withTitle: "Keep DNS and Quit")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn: operate(["--restore"], quitAfter: true)
        case .alertSecondButtonReturn: NSApplication.shared.terminate(nil)
        default: break
        }
    }

    func diagnostics() {
        Task {
            let output = await Task.detached { () -> String in
                let status = (try? CommandRunner.run(pathForHelper(), ["--status"]).output) ?? "Status unavailable"
                let backup = (try? CommandRunner.run(pathForHelper(), ["--backup"]).output) ?? "Backup unavailable"
                let dns = (try? CommandRunner.run("/usr/sbin/scutil", ["--dns"]).output) ?? "Effective DNS unavailable"
                return "QUIETDNS STATUS\n\(status)\nSAVED ORIGINAL AND APPLIED SETTINGS\n\(backup)\nEFFECTIVE MACOS RESOLVERS\n\(dns)\n\nConfigured DNS does not prove that BlueStacks, a VPN, Private Relay, or a browser uses it. In BlueStacks, visit https://adguard.com/en/test.html in its browser, then test the actual game. Restart BlueStacks after DNS changes."
            }.value
            DiagnosticsWindow.show(output)
        }
    }
}

// Resolve the bundled helper without capturing the main-actor model in a background task.
func pathForHelper() -> String { Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/quietdns-helper").path }

@MainActor
enum DiagnosticsWindow {
    static var window: NSWindow?
    static func show(_ text: String) {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 720, height: 500))
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        let content = NSTextView(frame: scroll.bounds)
        content.isEditable = false; content.isSelectable = true
        content.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        content.string = text; content.textContainerInset = NSSize(width: 16, height: 16)
        content.autoresizingMask = [.width]; scroll.documentView = content
        let result = NSWindow(contentRect: scroll.frame, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        result.title = "QuietDNS — DNS diagnostics"; result.contentView = scroll
        result.isReleasedWhenClosed = false; result.center(); result.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true); window = result
    }
}

struct ControlPanel: View {
    @ObservedObject var model: AppModel
    private var isOn: Bool { model.state == "on" }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: isOn ? "shield.lefthalf.filled" : "shield")
                    .font(.system(size: 32)).foregroundStyle(isOn ? Color.green : Color.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text("QuietDNS").font(.title2.bold())
                    Text(model.busy ? "Waiting for macOS…" : isOn ? "Filtering DNS is on" : model.state == "off" ? "Filtering DNS is off" : "Check DNS settings")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                if model.busy { ProgressView().controlSize(.small) }
            }
            Text(model.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let provider = model.savedProvider {
                Text("\(provider) · \(model.savedServices.joined(separator: ", "))").font(.caption).bold()
            }
            Button(action: model.toggle) {
                Text(model.hasBackup ? "Turn Off & Restore DNS" : "Turn On Ad Blocking")
                    .frame(maxWidth: .infinity).padding(.vertical, 5)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.busy || model.state == "loading" || model.state == "unknown")
            .accessibilityHint("macOS may ask for administrator approval to change DNS")
            if model.state == "recovery" || model.state == "unknown" {
                Button("Restore saved DNS anyway…") { model.forceRestore = true }
                    .disabled(model.busy)
            }
            Divider()
            Picker("DNS provider", selection: $model.provider) {
                Text("AdGuard DNS").tag("AdGuard DNS")
                Text("Custom IP addresses").tag("Custom DNS")
            }.disabled(model.hasBackup || model.busy)
            if model.provider != "AdGuard DNS" {
                TextField("DNS server IPs, separated by commas", text: $model.custom, axis: .vertical)
                    .lineLimit(2...3).textFieldStyle(.roundedBorder).disabled(model.hasBackup || model.busy)
                Text("Use a trusted plain DNS provider or a local filtering resolver. This app does not encrypt DNS.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            DisclosureGroup("Networks (\(model.selected.intersection(Set(model.services.map(\.id))).count) selected)") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(model.services, id: \.id) { service in
                        Toggle(service.name, isOn: Binding(
                            get: { model.selected.contains(service.id) },
                            set: { if $0 { model.selected.insert(service.id) } else { model.selected.remove(service.id) } }
                        ))
                    }
                    if model.services.isEmpty { Text("No enabled Wi-Fi or Ethernet services found.") }
                    Text("New adapters need to be selected next time. VPN and virtual interfaces are excluded.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(.top, 8)
            }.disabled(model.hasBackup || model.busy)
            Text("Blocks many ad and tracker domains. YouTube and other first-party ads can remain. VPNs, Private Relay, browsers, and BlueStacks may use their own DNS.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("macOS asks for administrator approval when changing DNS. Turn off before uninstalling.")
                .font(.caption2).foregroundStyle(.secondary)
            HStack {
                Button("Check DNS", action: model.diagnostics)
                Button("Help") {
                    NSWorkspace.shared.open(Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/START-HERE.html"))
                }
                Spacer()
                Button("Quit", action: model.quit)
            }.buttonStyle(.borderless).disabled(model.busy)
        }
        .padding(20).frame(width: 390)
        .alert("QuietDNS", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
        .confirmationDialog("Replace current DNS with the saved original settings?", isPresented: $model.forceRestore) {
            Button("Restore Saved DNS Anyway", role: .destructive) { model.operate(["--restore-force"]) }
            Button("Cancel", role: .cancel) { }
        } message: { Text("This replaces DNS edits made since QuietDNS was enabled. Use it only after reviewing the current settings.") }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    var item: NSStatusItem!
    let popover = NSPopover()
    var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self; item.button?.action = #selector(togglePopover)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: ControlPanel(model: model))
        model.changed = { [weak self] in self?.updateIcon() }
        model.refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.model.refresh() }
        }
        if CommandLine.arguments.contains("--show-panel") { togglePopover() }
    }

    func updateIcon() {
        let symbol = model.state == "on" ? "shield.lefthalf.filled" : model.hasBackup ? "exclamationmark.shield" : "shield"
        item.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "QuietDNS: \(model.state)")
        item.button?.toolTip = "QuietDNS — \(model.state == "on" ? "filtering DNS on" : model.state == "off" ? "off" : "check settings")"
    }

    @objc func togglePopover() {
        guard let button = item.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else { model.refresh(); popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY) }
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}
