import Foundation
import SystemConfiguration
import OSLog

@MainActor
protocol NetworkChangeObserving: AnyObject {
    func start(_ changed: @escaping @MainActor () -> Void)
    func stop()
}

@MainActor
private final class NetworkChangeCallback {
    var changed: (@MainActor () -> Void)?
    init(_ changed: @escaping @MainActor () -> Void) { self.changed = changed }
}

/// Local configuration notifications only: no probes, polling or VPN-specific rules.
@MainActor
final class NetworkConfigurationObserver: NetworkChangeObserving {
    private var store: SCDynamicStore?
    private var callback: NetworkChangeCallback?
    private let logger = Logger(subsystem: "app.duskshift.mac", category: "Location")
    var isObserving: Bool { store != nil }

    func start(_ changed: @escaping @MainActor () -> Void) {
        stop()
        let callback = NetworkChangeCallback(changed)
        var context = SCDynamicStoreContext(version: 0,
            info: Unmanaged.passUnretained(callback).toOpaque(),
            retain: { info in
                _ = Unmanaged<NetworkChangeCallback>.fromOpaque(info).retain()
                return info
            }, release: { info in
                Unmanaged<NetworkChangeCallback>.fromOpaque(info).release()
            }, copyDescription: nil)
        guard let store = SCDynamicStoreCreate(nil, "app.duskshift.mac.location-network" as CFString,
            { store, _, info in
                guard let info else { return }
                let callback = Unmanaged<NetworkChangeCallback>.fromOpaque(info).takeUnretainedValue()
                MainActor.assumeIsolated {
                    // A route exists; this does not claim Apple's location service is reachable.
                    let hasRoute = ["IPv4", "IPv6"].contains { family in
                        let state = SCDynamicStoreCopyValue(store, "State:/Network/Global/\(family)" as CFString) as? [String: Any]
                        return state?["PrimaryInterface"] as? String != nil
                    }
                    if hasRoute { callback.changed?() }
                }
            }, &context) else {
                logger.error("Could not create network configuration observer")
                return
            }
        let keys = ["State:/Network/Global/IPv4", "State:/Network/Global/IPv6", "State:/Network/Global/DNS"]
        let patterns = ["State:/Network/Service/.*/IPv4", "State:/Network/Service/.*/IPv6", "State:/Network/Service/.*/DNS"]
        guard SCDynamicStoreSetNotificationKeys(store, keys as CFArray, patterns as CFArray),
              SCDynamicStoreSetDispatchQueue(store, .main) else {
            logger.error("Could not register network configuration notifications")
            return
        }
        self.callback = callback
        self.store = store
    }

    func stop() {
        callback?.changed = nil
        if let store { SCDynamicStoreSetDispatchQueue(store, nil) }
        store = nil; callback = nil
    }
}
