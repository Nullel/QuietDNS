import Foundation
import Darwin
import QuietDNSCore

func emit<T: Encodable>(_ value: T) throws {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    print(String(decoding: try encoder.encode(value), as: UTF8.self))
}

struct ServiceInfo: Encodable {
    let id: String
    let name: String
    let eligible: Bool
    let enabled: Bool
    let servers: [String]
}

let usage = """
QuietDNS helper — macOS 14 or later
  --status                              Read settings and recovery status (no admin).
  --list                                List network services (no admin).
  --backup                              Show decoded original/applied settings (no admin).
  --enable PROVIDER IP[,IP...] ID [ID...] Configure selected physical services (admin).
  --restore                             Restore saved DNS; refuse conflicts (admin).
  --restore-force                       Explicitly replace conflicting DNS with backup (admin).
  --help
Use the menu-bar app for the normal macOS administrator prompt. No background daemon is installed.
"""

do {
    let args = Array(CommandLine.arguments.dropFirst())
    if args == ["--help"] || args.isEmpty { print(usage); exit(0) }
    let journal = FileJournalStore()
    let network = try SystemNetworkStore()
    let engine = DNSEngine(network: network, journal: journal)
    if args == ["--status"] {
        try emit(engine.status())
    } else if args == ["--list"] {
        try emit(network.services().map { ServiceInfo(id: $0.id, name: $0.name, eligible: $0.eligible, enabled: $0.enabled, servers: $0.dns.servers) })
    } else if args == ["--backup"] {
        if let backup = try journal.load() {
            let decoded = try backup.services.map { service -> [String: Any] in
                ["serviceID": service.id, "name": service.name,
                 "originalConfigurationWasAbsent": service.original.propertyList == nil,
                 "original": try service.original.dictionary() ?? [:],
                 "applied": try service.applied.dictionary() ?? [:]]
            }
            let data = try PropertyListSerialization.data(fromPropertyList: decoded, format: .xml, options: 0)
            print(String(decoding: data, as: UTF8.self))
        } else { print("No DNS backup exists. QuietDNS has no saved settings to restore.") }
    } else {
        guard geteuid() == 0 else { throw QuietError("Administrator access is required. Use the QuietDNS app or run this helper with sudo.") }
        // Do not allow root execution to write application/user caches via injected environment values.
        umask(0o022)
        try journal.withExclusiveLock {
            if args == ["--restore"] || args == ["--restore-force"] {
                try engine.restore(force: args == ["--restore-force"])
            } else if args.count >= 4, args[0] == "--enable" {
                try engine.enable(servers: DNSProvider.parse(args[2]), provider: args[1], serviceIDs: Array(args.dropFirst(3)))
            } else { throw QuietError(usage) }
        }
        // Cache flush is best effort. DNS settings are already committed and can be restored.
        _ = try? CommandRunner.run("/usr/bin/dscacheutil", ["-flushcache"])
        _ = try? CommandRunner.run("/usr/bin/killall", ["-HUP", "mDNSResponder"])
        print("DNS operation completed. Restart apps that cache DNS, including BlueStacks.")
    }
} catch {
    FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
    exit(1)
}
