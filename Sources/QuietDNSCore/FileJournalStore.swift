import Foundation
import Darwin

/// The only privileged filesystem destination. No user-supplied paths or environment overrides.
public final class FileJournalStore: JournalStore {
    public static let systemDirectory = URL(fileURLWithPath: "/Library/Application Support/QuietDNS", isDirectory: true)
    public let directory: URL
    private let owner: uid_t
    public var journalURL: URL { directory.appendingPathComponent("recovery.plist") }

    // Injectable directory/owner only for tests. The helper always uses the defaults.
    public init(directory: URL = FileJournalStore.systemDirectory, owner: uid_t = 0) {
        self.directory = directory; self.owner = owner
    }

    private func posix(_ action: String) -> QuietError {
        QuietError("\(action): \(String(cString: strerror(errno))). Keep the DNS recovery file.")
    }

    private func safe(_ info: stat, directory: Bool) -> Bool {
        let kind = info.st_mode & S_IFMT
        return info.st_uid == owner && info.st_mode & 0o022 == 0 &&
            kind == (directory ? S_IFDIR : S_IFREG)
    }

    private func directoryExists() throws -> Bool {
        var info = stat()
        if lstat(directory.path, &info) != 0 {
            if errno == ENOENT { return false }
            throw posix("Inspect recovery directory")
        }
        guard safe(info, directory: true) else {
            throw QuietError("The recovery directory has unsafe ownership, permissions, or a symbolic link. Nothing was changed.")
        }
        return true
    }

    public func prepare() throws {
        if try !directoryExists() {
            guard mkdir(directory.path, 0o755) == 0 || errno == EEXIST else { throw posix("Create recovery directory") }
            guard try directoryExists() else { throw QuietError("Recovery directory is missing.") }
        }
    }

    public func withExclusiveLock<T>(_ work: () throws -> T) throws -> T {
        try prepare()
        let fd = open(directory.appendingPathComponent("operation.lock").path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o644)
        guard fd >= 0 else { throw posix("Open operation lock") }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, safe(info, directory: false), info.st_nlink == 1 else {
            throw QuietError("Unsafe operation lock. Nothing was changed.")
        }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            throw QuietError("Another DNS operation is running. Wait for it to finish.")
        }
        defer { flock(fd, LOCK_UN) }
        return try work()
    }

    public func load() throws -> Journal? {
        guard try directoryExists() else { return nil }
        let fd = open(journalURL.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        if fd < 0 {
            if errno == ENOENT { return nil }
            throw posix("Read DNS recovery file")
        }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        var info = stat()
        guard fstat(fd, &info) == 0, safe(info, directory: false), info.st_nlink == 1,
              info.st_size > 0, info.st_size <= 1_048_576 else {
            throw QuietError("The DNS recovery file is unsafe or damaged. Nothing was changed.")
        }
        guard let data = try handle.readToEnd() else { throw QuietError("Empty recovery file.") }
        let value = try PropertyListDecoder().decode(Journal.self, from: data)
        try value.validate()
        return value
    }

    private func syncDirectory() throws {
        let fd = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw posix("Open recovery directory") }
        defer { close(fd) }
        guard fsync(fd) == 0 else { throw posix("Sync recovery directory") }
    }

    public func save(_ journal: Journal) throws {
        try journal.validate()
        try prepare()
        let data = try PropertyListEncoder().encode(journal)
        let temporary = directory.appendingPathComponent(".recovery-\(UUID().uuidString)")
        let fd = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o644)
        guard fd >= 0 else { throw posix("Create recovery file") }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { unlink(temporary.path) }
        try handle.write(contentsOf: data)
        guard fsync(fd) == 0 else { throw posix("Save recovery file") }
        guard rename(temporary.path, journalURL.path) == 0 else { throw posix("Publish recovery file") }
        try syncDirectory()
    }

    public func remove() throws {
        guard try directoryExists() else { return }
        if unlink(journalURL.path) != 0 && errno != ENOENT { throw posix("Remove completed recovery file") }
        try syncDirectory()
    }
}
