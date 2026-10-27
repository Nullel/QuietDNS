import Foundation

public protocol NetworkStore: AnyObject {
    func lock() throws
    func unlock()
    func services() throws -> [NetworkService]
    func setDNS(_ dns: DNSConfiguration, serviceID: String) throws
    func commitAndApply() throws
}

public protocol JournalStore: AnyObject {
    func load() throws -> Journal?
    func save(_ journal: Journal) throws
    func remove() throws
}

public struct Status: Codable {
    public let state: String
    public let detail: String
    public let provider: String?
    public let services: [String]
    public let servers: [String]
    public var hasBackup: Bool { state != "off" }
}

public final class DNSEngine {
    private let network: NetworkStore
    private let journal: JournalStore

    public init(network: NetworkStore, journal: JournalStore) {
        self.network = network; self.journal = journal
    }

    public func status() throws -> Status {
        guard let saved = try journal.load() else {
            return Status(state: "off", detail: "Original DNS settings are in use.", provider: nil, services: [], servers: [])
        }
        try saved.validate()
        let current = Dictionary(uniqueKeysWithValues: try network.services().map { ($0.id, $0) })
        let intact = saved.services.allSatisfy { entry in
            guard let service = current[entry.id] else { return false }
            return service.dns == entry.applied
        }
        let state = saved.phase == .enabled && intact ? "on" : "recovery"
        return Status(state: state,
                      detail: state == "on" ? "Filtering DNS is configured. Apps can bypass system DNS." :
                        "DNS changed or an operation was interrupted. Restore saved settings before enabling again.",
                      provider: saved.provider, services: saved.services.map(\.name), servers: saved.services.first?.applied.servers ?? [])
    }

    public func enable(servers: [String], provider: String, serviceIDs: [String]) throws {
        let servers = try DNSProvider.validate(servers)
        guard !provider.isEmpty, provider.utf8.count <= 100 else { throw QuietError("Invalid provider name.") }
        try network.lock()
        defer { network.unlock() }
        guard try journal.load() == nil else {
            throw QuietError("A DNS backup already exists. Restore it before enabling again; the original backup was kept.")
        }
        let available = try network.services()
        let ids = Set(serviceIDs)
        let selected = available.filter { ids.contains($0.id) && $0.eligible && $0.enabled }
        guard !ids.isEmpty, ids.count == selected.count else {
            throw QuietError("Select existing, enabled Wi-Fi or Ethernet services. VPN and virtual interfaces are excluded.")
        }
        let entries = try selected.map {
            SavedService(id: $0.id, name: $0.name, original: $0.dns, applied: try $0.dns.replacingServers(servers))
        }
        guard entries.contains(where: { $0.original != $0.applied }) else {
            throw QuietError("These DNS servers are already configured. QuietDNS did not create them and has nothing to restore.")
        }
        var saved = Journal(provider: provider, services: entries)
        // Durable write-ahead record, before any system setting changes.
        try journal.save(saved)
        do {
            for entry in entries { try network.setDNS(entry.applied, serviceID: entry.id) }
            try network.commitAndApply()
            saved.phase = .enabled
            try journal.save(saved)
        } catch {
            let failure = error.localizedDescription
            do {
                for entry in entries { try network.setDNS(entry.original, serviceID: entry.id) }
                try network.commitAndApply()
                try journal.remove()
            } catch {
                throw QuietError("Could not enable filtering: \(failure). Rollback needs attention: \(error.localizedDescription). The recovery file was kept. Use Restore saved DNS.")
            }
            throw QuietError("Could not enable filtering: \(failure). The previous DNS settings were restored.")
        }
    }

    /// Normal restore refuses to overwrite unrelated edits. Force is an explicit recovery choice.
    public func restore(force: Bool = false) throws {
        try network.lock()
        defer { network.unlock() }
        guard var saved = try journal.load() else { return }
        try saved.validate()
        let current = Dictionary(uniqueKeysWithValues: try network.services().map { ($0.id, $0) })
        let missing = saved.services.filter { current[$0.id] == nil }
        guard missing.isEmpty else {
            throw QuietError("A saved network service was removed (\(missing.map(\.name).joined(separator: ", "))). Restore that service or recover manually; the backup was kept.")
        }
        let conflicts = saved.services.filter { entry in
            let dns = current[entry.id]!.dns
            return dns != entry.applied && dns != entry.original
        }
        guard force || conflicts.isEmpty else {
            throw QuietError("Another app or person changed DNS for \(conflicts.map(\.name).joined(separator: ", ")). Restore was stopped to preserve those edits. Review them, then choose Restore saved DNS anyway if wanted.")
        }
        saved.phase = .restoring
        try journal.save(saved)
        // If interrupted, the journal stays. A repeat restore is safe and idempotent.
        for entry in saved.services { try network.setDNS(entry.original, serviceID: entry.id) }
        try network.commitAndApply()
        try journal.remove()
    }
}
