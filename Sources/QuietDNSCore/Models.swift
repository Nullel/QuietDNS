import Foundation
import Darwin

public struct QuietError: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// A missing DNS configuration differs from an explicitly empty dictionary.
/// Keep the entire property list, including search domains and supplemental keys.
public struct DNSConfiguration: Codable, Equatable {
    public let propertyList: Data?

    public init(_ dictionary: [String: Any]?) throws {
        propertyList = try dictionary.map {
            try PropertyListSerialization.data(fromPropertyList: $0, format: .binary, options: 0)
        }
    }

    public func dictionary() throws -> [String: Any]? {
        guard let propertyList else { return nil }
        guard let value = try PropertyListSerialization.propertyList(from: propertyList, format: nil) as? [String: Any] else {
            throw QuietError("The saved DNS configuration is not a dictionary. Keep the recovery file.")
        }
        return value
    }

    public var servers: [String] { (try? dictionary()?["ServerAddresses"] as? [String]) ?? [] }

    public func replacingServers(_ servers: [String]) throws -> DNSConfiguration {
        var value = try dictionary() ?? [:]
        value["ServerAddresses"] = servers
        return try DNSConfiguration(value)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard let a = try? lhs.dictionary(), let b = try? rhs.dictionary() else {
            return lhs.propertyList == nil && rhs.propertyList == nil
        }
        return NSDictionary(dictionary: a).isEqual(to: b)
    }
}

public struct NetworkService {
    public let id: String
    public let name: String
    public let eligible: Bool
    public let enabled: Bool
    public let dns: DNSConfiguration

    public init(id: String, name: String, eligible: Bool = true, enabled: Bool = true, dns: DNSConfiguration) {
        self.id = id; self.name = name; self.eligible = eligible; self.enabled = enabled; self.dns = dns
    }
}

public struct SavedService: Codable {
    public let id: String
    public let name: String
    public let original: DNSConfiguration
    public let applied: DNSConfiguration
}

public struct Journal: Codable {
    public enum Phase: String, Codable { case applying, enabled, restoring }
    public let version: Int
    public let createdAt: Date
    public let provider: String
    public var phase: Phase
    public let services: [SavedService]

    public init(provider: String, services: [SavedService]) {
        version = 1; createdAt = Date(); self.provider = provider
        phase = .applying; self.services = services
    }

    public func validate() throws {
        guard version == 1, !services.isEmpty, services.count <= 100,
              Set(services.map(\.id)).count == services.count else {
            throw QuietError("Unsupported or damaged recovery file. Nothing was changed; keep the file for recovery.")
        }
        for service in services {
            _ = try service.original.dictionary()
            _ = try service.applied.dictionary()
            _ = try DNSProvider.validate(service.applied.servers)
        }
    }
}

public enum DNSProvider {
    public static let adGuard = ["94.140.14.14", "94.140.15.15", "2a10:50c0::ad1:ff", "2a10:50c0::ad2:ff"]

    public static func parse(_ value: String) throws -> [String] {
        try validate(value.split(whereSeparator: { $0.isWhitespace || $0 == "," }).map(String.init))
    }

    public static func validate(_ addresses: [String]) throws -> [String] {
        guard !addresses.isEmpty, addresses.count <= 8 else {
            throw QuietError("Enter between 1 and 8 DNS server IP addresses.")
        }
        var result = [String]()
        for address in addresses {
            var v4 = in_addr(); var v6 = in6_addr()
            guard address.utf8.count < 64,
                  inet_pton(AF_INET, address, &v4) == 1 || inet_pton(AF_INET6, address, &v6) == 1 else {
                throw QuietError("Invalid DNS IP address: \(address). Use IPv4 or IPv6 addresses, not URLs or hostnames.")
            }
            guard address != "0.0.0.0", address != "::", address != "255.255.255.255",
                  !(224...239).contains(Int(address.split(separator: ".").first ?? "") ?? -1),
                  !address.lowercased().hasPrefix("ff") else {
                throw QuietError("\(address) is not a usable DNS server address.")
            }
            if !result.contains(address) { result.append(address) }
        }
        return result
    }
}

public enum Escaping {
    public static func shell(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    public static func appleScript(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r") + "\""
    }
}
