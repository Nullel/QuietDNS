import Foundation
import SystemConfiguration

public final class SystemNetworkStore: NetworkStore {
    private let preferences: SCPreferences
    private var locked = false

    public init() throws {
        guard let preferences = SCPreferencesCreate(nil, "QuietDNS" as CFString, nil) else {
            throw Self.failure("Read network settings")
        }
        self.preferences = preferences
    }

    private static func failure(_ action: String) -> QuietError {
        QuietError("\(action): \(String(cString: SCErrorString(SCError()))). No administrator access or a managed network may prevent this change.")
    }

    public func lock() throws {
        guard SCPreferencesLock(preferences, false) else { throw Self.failure("Lock network settings") }
        locked = true
        SCPreferencesSynchronize(preferences)
    }

    public func unlock() {
        if locked { SCPreferencesUnlock(preferences); locked = false }
    }

    public func services() throws -> [NetworkService] {
        guard let services = SCNetworkServiceCopyAll(preferences) as? [SCNetworkService] else {
            throw Self.failure("List network services")
        }
        return try services.map { service in
            let interface = SCNetworkServiceGetInterface(service)
            let type = interface.flatMap(SCNetworkInterfaceGetInterfaceType) as String?
            let device = interface.flatMap(SCNetworkInterfaceGetBSDName) as String?
            let physical = (type == kSCNetworkInterfaceTypeEthernet as String || type == kSCNetworkInterfaceTypeIEEE80211 as String)
                && (device?.hasPrefix("en") == true)
            let proto = SCNetworkServiceCopyProtocol(service, kSCNetworkProtocolTypeDNS)
            let dns = proto.flatMap(SCNetworkProtocolGetConfiguration) as? [String: Any]
            guard let id = SCNetworkServiceGetServiceID(service) as String? else {
                throw QuietError("A network service has no stable identifier. Nothing was changed.")
            }
            return NetworkService(id: id,
                                  name: (SCNetworkServiceGetName(service) as String?) ?? "Unnamed service",
                                  eligible: physical && proto.map(SCNetworkProtocolGetEnabled) == true,
                                  enabled: SCNetworkServiceGetEnabled(service),
                                  dns: try DNSConfiguration(dns))
        }.sorted { $0.name < $1.name }
    }

    public func setDNS(_ dns: DNSConfiguration, serviceID: String) throws {
        guard locked else { throw QuietError("Network write attempted without the preferences lock.") }
        guard let service = SCNetworkServiceCopy(preferences, serviceID as CFString),
              let proto = SCNetworkServiceCopyProtocol(service, kSCNetworkProtocolTypeDNS) else {
            throw QuietError("The saved network service no longer exists: \(serviceID)")
        }
        let config = try dns.dictionary()
        guard SCNetworkProtocolSetConfiguration(proto, config.map { $0 as CFDictionary }) else {
            throw Self.failure("Set DNS for \(serviceID)")
        }
    }

    public func commitAndApply() throws {
        guard locked else { throw QuietError("Network commit attempted without the preferences lock.") }
        guard SCPreferencesCommitChanges(preferences) else { throw Self.failure("Save DNS") }
        guard SCPreferencesApplyChanges(preferences) else { throw Self.failure("Apply DNS") }
    }
}
