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
    /// Minutes until empty / full; nil while macOS is still calculating.
    @Published private(set) var minutesToEmpty: Int?
    @Published private(set) var minutesToFull: Int?
    @Published private(set) var isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

    var onPluggedIn: (() -> Void)?
    var onLowBattery: ((Int) -> Void)?
    var onLowPowerModeChange: ((Bool) -> Void)?

    private static let lowThresholds = [20, 10, 5]
    private var runLoopSource: CFRunLoopSource?
    private var initialized = false
    private var alertedThresholds = Set<Int>()
    private var powerObserver: NSObjectProtocol?

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
        powerObserver = NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil,
                                                               queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let enabled = ProcessInfo.processInfo.isLowPowerModeEnabled
                guard enabled != self.isLowPowerMode else { return }
                self.isLowPowerMode = enabled
                self.onLowPowerModeChange?(enabled)
            }
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

    /// Short state: Charging, Charged, On power adapter or On battery.
    var statusText: String {
        if isPluggedIn {
            if level >= 100 || (!isCharging && level >= 80) { return isCharging ? "Charged" : "On power adapter" }
            return "Charging"
        }
        return "On battery"
    }

    /// Time left, or nil when there is nothing to estimate (fully charged / on the adapter).
    var remainingText: String? {
        if isPluggedIn {
            if level >= 100 || (!isCharging && level >= 80) { return nil }
            guard let minutes = minutesToFull else { return "Calculating…" }
            return "\(Self.format(minutes)) until full"
        }
        guard let minutes = minutesToEmpty else { return "Calculating…" }
        return "\(Self.format(minutes)) remaining"
    }

    private static func format(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }

    func refresh() { update() }

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
            let toEmpty = desc[kIOPSTimeToEmptyKey] as? Int ?? -1
            let toFull = desc[kIOPSTimeToFullChargeKey] as? Int ?? -1
            // The dictionary reports -1 while macOS recomputes; the system estimate (seconds) is often ready sooner.
            let estimate = IOPSGetTimeRemainingEstimate()
            let fallback = estimate > 0 ? Int((estimate / 60).rounded()) : -1
            minutesToEmpty = toEmpty > 0 ? toEmpty : (isPluggedIn || fallback <= 0 ? nil : fallback)
            minutesToFull = toFull > 0 ? toFull : nil
        }
        hasBattery = found
        guard found else { return }
        if initialized, isPluggedIn, !wasPlugged { onPluggedIn?() }
        if isPluggedIn {
            alertedThresholds.removeAll()
        } else if let threshold = Self.lowThresholds.filter({ level <= $0 }).min(), !alertedThresholds.contains(threshold) {
            // Mark every crossed threshold so we alert once per level, not again for higher ones.
            Self.lowThresholds.filter { level <= $0 }.forEach { alertedThresholds.insert($0) }
            if initialized { onLowBattery?(level) }
        }
    }
}
