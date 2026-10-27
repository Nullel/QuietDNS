import Foundation
import Testing
@testable import QuietDNSCore

final class FakeNetwork: NetworkStore {
    var values: [NetworkService]
    var committed: [NetworkService]
    var locked = false
    var commits = 0
    var failCommits = Set<Int>()
    var failSetOnce = false
    var beforeSet: (() throws -> Void)?
    init(_ values: [NetworkService]) { self.values = values; committed = values }
    func lock() throws {
        guard !locked else { throw QuietError("busy") }; locked = true; values = committed
    }
    func unlock() { locked = false }
    func services() throws -> [NetworkService] { locked ? values : committed }
    func setDNS(_ dns: DNSConfiguration, serviceID: String) throws {
        checkTrue(locked)
        try beforeSet?()
        if failSetOnce { failSetOnce = false; throw QuietError("set failed") }
        guard let i = values.firstIndex(where: { $0.id == serviceID }) else { throw QuietError("missing") }
        let old = values[i]
        values[i] = NetworkService(id: old.id, name: old.name, eligible: old.eligible, enabled: old.enabled, dns: dns)
    }
    func commitAndApply() throws {
        checkTrue(locked); commits += 1
        // Model commit succeeding but apply failing: rollback must undo persistent settings.
        committed = values
        if failCommits.contains(commits) { throw QuietError("apply failed") }
    }
}

final class FakeJournal: JournalStore {
    var value: Journal?
    var saves = 0
    var failSaves = Set<Int>()
    var failRemove = false
    func load() throws -> Journal? { value }
    func save(_ journal: Journal) throws {
        saves += 1
        if failSaves.contains(saves) { throw QuietError("disk full") }; value = journal
    }
    func remove() throws {
        if failRemove { throw QuietError("delete failed") }; value = nil
    }
}

struct EngineTests {
    func fixture() throws -> (DNSEngine, FakeNetwork, FakeJournal, [NetworkService]) {
        let services = [
            NetworkService(id: "wifi", name: "Wi-Fi with 'quotes'", dns: try DNSConfiguration(nil)),
            NetworkService(id: "wired", name: "Ethernet", dns: try DNSConfiguration([
                "ServerAddresses": ["192.168.1.1", "fd00::1"], "SearchDomains": ["office.example"], "ServerPort": 53
            ])),
            NetworkService(id: "vpn", name: "VPN", eligible: false, dns: try DNSConfiguration(["ServerAddresses": ["10.0.0.1"]]))
        ]
        let network = FakeNetwork(services); let journal = FakeJournal()
        return (DNSEngine(network: network, journal: journal), network, journal, services)
    }

    func enable(_ engine: DNSEngine) throws {
        try engine.enable(servers: DNSProvider.adGuard, provider: "AdGuard DNS", serviceIDs: ["wifi", "wired"])
    }

    @Test func testEnableAndExactRestoreOfAutomaticStaticIPv6AndSearchSettings() throws {
        let (engine, network, journal, original) = try fixture()
        try enable(engine)
        checkEqual(try engine.status().state, "on")
        checkEqual(journal.value?.phase, .enabled)
        checkEqual(network.committed[1].dns.servers, DNSProvider.adGuard)
        checkEqual(try network.committed[1].dns.dictionary()?["SearchDomains"] as? [String], ["office.example"])
        checkEqual(network.committed[2].dns, original[2].dns)
        try engine.restore()
        checkNil(journal.value)
        for i in original.indices { checkEqual(network.committed[i].dns, original[i].dns) }
        checkNil(network.committed[0].dns.propertyList)
        checkEqual(try engine.status().state, "off")
        checkFalse(network.locked)
    }

    @Test func testBackupIsDurableBeforeFirstNetworkWrite() throws {
        let (engine, network, journal, _) = try fixture()
        network.beforeSet = { checkEqual(journal.value?.phase, .applying) }
        try enable(engine)
    }

    @Test func testAlreadyEnabledNeverOverwritesOriginalBackup() throws {
        let (engine, _, journal, original) = try fixture()
        try enable(engine)
        checkThrows(try enable(engine))
        checkEqual(journal.value?.services.first?.original, original[0].dns)
        checkEqual(journal.saves, 2)
    }

    @Test func testFailedApplyRollsBack() throws {
        let (engine, network, journal, original) = try fixture()
        network.failCommits = [1]
        checkThrows(try enable(engine))
        checkNil(journal.value)
        checkEqual(network.committed[0].dns, original[0].dns)
        checkEqual(network.committed[1].dns, original[1].dns)
    }

    @Test func testFailedSetRollsBack() throws {
        let (engine, network, journal, original) = try fixture()
        network.failSetOnce = true
        checkThrows(try enable(engine))
        checkNil(journal.value)
        checkEqual(network.committed[0].dns, original[0].dns)
    }

    @Test func testFailedRollbackRetainsRecoveryAndCanRetry() throws {
        let (engine, network, journal, original) = try fixture()
        network.failCommits = [1, 2]
        checkThrows(try enable(engine))
        checkNotNil(journal.value)
        checkEqual(try engine.status().state, "recovery")
        try engine.restore()
        checkNil(journal.value)
        checkEqual(network.committed[1].dns, original[1].dns)
    }

    @Test func testDiskFailureBeforeBackupPreventsDNSWrites() throws {
        let (engine, network, _, original) = try fixture()
        let journal = FakeJournal(); journal.failSaves = [1]
        let failing = DNSEngine(network: network, journal: journal)
        checkThrows(try enable(failing))
        checkEqual(network.commits, 0)
        checkEqual(network.committed[0].dns, original[0].dns)
        checkEqual(try engine.status().state, "off")
    }

    @Test func testFailureSavingEnabledPhaseRollsBack() throws {
        let (engine, network, journal, original) = try fixture()
        journal.failSaves = [2]
        checkThrows(try enable(engine))
        checkNil(journal.value)
        checkEqual(network.committed[1].dns, original[1].dns)
    }

    @Test func testExternalEditRequiresExplicitForce() throws {
        let (engine, network, journal, original) = try fixture()
        try enable(engine)
        network.committed[0] = NetworkService(id: "wifi", name: "Renamed Wi-Fi", dns: try DNSConfiguration(["ServerAddresses": ["1.1.1.1"]]))
        checkEqual(try engine.status().state, "recovery")
        checkThrows(try engine.restore())
        checkEqual(network.committed[0].dns.servers, ["1.1.1.1"])
        checkNotNil(journal.value)
        try engine.restore(force: true)
        checkEqual(network.committed[0].dns, original[0].dns)
    }

    @Test func testInterruptedEnableRecoversMixedOldAndNewSettings() throws {
        let (engine, network, journal, original) = try fixture()
        try enable(engine)
        journal.value?.phase = .applying
        network.committed[1] = original[1]
        checkEqual(try engine.status().state, "recovery")
        try engine.restore()
        checkEqual(network.committed[0].dns, original[0].dns)
    }

    @Test func testFailedRestoreKeepsJournalAndRetryIsIdempotent() throws {
        let (engine, network, journal, original) = try fixture()
        try enable(engine); network.failCommits = [2]
        checkThrows(try engine.restore())
        checkEqual(journal.value?.phase, .restoring)
        try engine.restore(); try engine.restore()
        checkNil(journal.value)
        checkEqual(network.committed[1].dns, original[1].dns)
    }

    @Test func testMissingServiceRetainsBackupEvenWithForce() throws {
        let (engine, network, journal, _) = try fixture()
        try enable(engine); network.committed.removeFirst()
        checkThrows(try engine.restore(force: true))
        checkNotNil(journal.value)
    }

    @Test func testVPNAndStaleSelectionRejectedBeforeBackup() throws {
        let (engine, network, journal, _) = try fixture()
        for ids in [["vpn"], ["missing"], []] {
            checkThrows(try engine.enable(servers: DNSProvider.adGuard, provider: "test", serviceIDs: ids))
        }
        checkNil(journal.value); checkEqual(network.commits, 0)
    }

    @Test func testRestoreByServiceIDSurvivesRename() throws {
        let (engine, network, _, original) = try fixture()
        try enable(engine)
        network.committed[0] = NetworkService(id: "wifi", name: "New Name", dns: network.committed[0].dns)
        try engine.restore()
        checkEqual(network.committed[0].dns, original[0].dns)
        checkEqual(network.committed[0].name, "New Name")
    }

    @Test func testNilAndEmptyDNSAreDistinctAndRoundTrip() throws {
        checkNotEqual(try DNSConfiguration(nil), try DNSConfiguration([:]))
        let a = try DNSConfiguration(["SearchDomains": ["a"], "ServerAddresses": ["::1"]])
        let b = try DNSConfiguration(["ServerAddresses": ["::1"], "SearchDomains": ["a"]])
        checkEqual(a, b)
        checkEqual(try PropertyListDecoder().decode(DNSConfiguration.self, from: PropertyListEncoder().encode(a)), a)
    }

    @Test func testValidationAndLocalResolverSupport() throws {
        checkEqual(try DNSProvider.parse("127.0.0.1, ::1\n94.140.14.14 127.0.0.1"), ["127.0.0.1", "::1", "94.140.14.14"])
        for value in ["", "dns.adguard-dns.com", "https://dns.example/dns-query", "1.2.3.4; rm -rf /", "0.0.0.0", "::", "224.0.0.1", "ff02::1"] {
            checkThrows(try DNSProvider.parse(value), value)
        }
    }

    @Test func testAlreadySameServersDoesNotCreateMisleadingBackup() throws {
        let (engine, network, journal, _) = try fixture()
        network.committed[0] = NetworkService(id: "wifi", name: "Wi-Fi", dns: try DNSConfiguration(["ServerAddresses": DNSProvider.adGuard]))
        checkThrows(try engine.enable(servers: DNSProvider.adGuard, provider: "test", serviceIDs: ["wifi"]))
        checkNil(journal.value)
    }

    @Test func testShellEscapingPreventsInjectionAndPreservesQuotes() throws {
        let payload = "single ' double \" newline\n$(touch /tmp/should-not-exist) `echo not-run` $HOME"
        let command = "/usr/bin/printf %s " + Escaping.shell(payload)
        let result = try CommandRunner.run("/bin/sh", ["-c", command])
        checkEqual(result.code, 0); checkEqual(result.output, payload)
        checkTrue(Escaping.appleScript(command).hasPrefix("\""))
        // Compile and evaluate AppleScript text only, with no shell or administrator action.
        let apple = try CommandRunner.run("/usr/bin/osascript", ["-e", "return " + Escaping.appleScript(command)])
        checkEqual(apple.code, 0)
        checkEqual(apple.output.trimmingCharacters(in: .newlines), command)
    }
}
