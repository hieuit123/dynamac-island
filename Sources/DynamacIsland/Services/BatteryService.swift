import Combine
import Foundation
import IOKit.ps

/// Battery state driven by IOKit power-source notifications (no polling).
@MainActor
final class BatteryService: ObservableObject {
    @Published private(set) var hasBattery = false
    @Published private(set) var level = 0
    @Published private(set) var isCharging = false
    @Published private(set) var isPluggedIn = false

    var onPluggedIn: (() -> Void)?
    private var runLoopSource: CFRunLoopSource?
    private var initialized = false

    init() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            let service = Unmanaged<BatteryService>.fromOpaque(ctx).takeUnretainedValue()
            MainActor.assumeIsolated { service.update() }
        }, context)?.takeRetainedValue() {
            runLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
        update()
        initialized = true
    }

    var symbolName: String {
        if isCharging || isPluggedIn { return "battery.100percent.bolt" }
        switch level {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    private func update() {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            hasBattery = false
            return
        }
        let wasPlugged = isPluggedIn
        var found = false
        for ps in list {
            guard let desc = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  desc[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            found = true
            let current = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maxCap = max(desc[kIOPSMaxCapacityKey] as? Int ?? 100, 1)
            level = Int((Double(current) / Double(maxCap) * 100).rounded())
            isCharging = desc[kIOPSIsChargingKey] as? Bool ?? false
            isPluggedIn = desc[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
        }
        hasBattery = found
        if initialized, found, isPluggedIn, !wasPlugged { onPluggedIn?() }
    }
}
