import Foundation
import Testing
import Darwin
@testable import QuietDNSCore

final class JournalTests {
    var root: URL!
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("QuietDNS-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    }
    deinit { try? FileManager.default.removeItem(at: root) }
    func saved() throws -> Journal {
        Journal(provider: "test", services: [SavedService(id: "wifi", name: "Wi-Fi", original: try DNSConfiguration(nil), applied: try DNSConfiguration(["ServerAddresses": ["127.0.0.1"]]))])
    }
    func store(_ name: String = "state") -> FileJournalStore {
        FileJournalStore(directory: root.appendingPathComponent(name), owner: getuid())
    }
    @Test func testAtomicFileRoundTripAndRemoval() throws {
        let state = store()
        checkNil(try state.load())
        try state.withExclusiveLock { try state.save(saved()) }
        checkEqual(try state.load()?.provider, "test")
        checkNil(try state.load()?.services[0].original.propertyList)
        try state.withExclusiveLock { try state.remove() }
        checkNil(try state.load())
    }
    @Test func testRejectDirectorySymlink() throws {
        let target = root.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("state"), withDestinationURL: target)
        checkThrows(try store().load())
    }
    @Test func testRejectJournalSymlinkAndWritableRecoveryFile() throws {
        let state = store(); try state.prepare()
        let target = root.appendingPathComponent("target")
        try Data("not a journal".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: state.journalURL, withDestinationURL: target)
        checkThrows(try state.load())
        try FileManager.default.removeItem(at: state.journalURL)
        try state.save(saved()); checkEqual(chmod(state.journalURL.path, 0o666), 0)
        checkThrows(try state.load())
    }
    @Test func testRejectWritableDirectoryAndDamagedJournal() throws {
        let state = store(); try state.prepare()
        checkEqual(chmod(state.directory.path, 0o777), 0)
        checkThrows(try state.load())
        checkEqual(chmod(state.directory.path, 0o755), 0)
        try Data("bad".utf8).write(to: state.journalURL)
        checkThrows(try state.load())
    }
    @Test func testConcurrentOperationRejected() throws {
        let state = store()
        try state.withExclusiveLock {
            checkThrows(try store().withExclusiveLock { })
        }
    }
}
