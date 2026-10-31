import AppKit
import IOBluetooth

/// Shows a live activity when Bluetooth audio/input devices connect or disconnect (notification-driven).
/// AirPods battery levels come from IOBluetoothDevice's undocumented battery properties when available.
@MainActor
final class BluetoothMonitor: NSObject {
    var onChange: ((_ name: String, _ symbol: String, _ battery: Int?, _ connected: Bool) -> Void)?

    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:]
    private var startDate = Date()

    func start() {
        guard connectNotification == nil else { return }
        startDate = Date()
        connectNotification = IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(deviceConnected(_:device:)))
    }

    func stop() {
        connectNotification?.unregister()
        connectNotification = nil
        disconnectNotifications.values.forEach { $0.unregister() }
        disconnectNotifications.removeAll()
    }

    @objc private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        let address = device.addressString ?? UUID().uuidString
        disconnectNotifications[address]?.unregister()
        disconnectNotifications[address] = device.register(forDisconnectNotification: self,
                                                           selector: #selector(deviceDisconnected(_:device:)))
        // Registration reports already-connected devices immediately; don't announce those.
        guard Date().timeIntervalSince(startDate) > 3 else { return }
        announce(device, connected: true)
        // Battery values usually arrive a moment after the connection.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard device.isConnected(), let battery = Self.battery(of: device) else { return }
            self?.onChange?(Self.name(of: device), Self.symbol(for: device), battery, true)
        }
    }

    @objc private func deviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        notification.unregister()
        if let address = device.addressString { disconnectNotifications[address] = nil }
        announce(device, connected: false)
    }

    private func announce(_ device: IOBluetoothDevice, connected: Bool) {
        onChange?(Self.name(of: device), Self.symbol(for: device), connected ? Self.battery(of: device) : nil, connected)
    }

    private static func name(of device: IOBluetoothDevice) -> String { device.name ?? "Bluetooth device" }

    static func battery(of device: IOBluetoothDevice) -> Int? {
        let keys = ["batteryPercentSingle", "batteryPercentCombined", "batteryPercentLeft", "batteryPercentRight"]
        let values = keys.compactMap { key -> Int? in
            guard device.responds(to: NSSelectorFromString(key)), let value = device.value(forKey: key) as? Int, value > 0 else { return nil }
            return value
        }
        return values.min()
    }

    static func symbol(for device: IOBluetoothDevice) -> String {
        let name = (device.name ?? "").lowercased()
        if name.contains("airpods max") { return "airpods.max" }
        if name.contains("airpods pro") { return "airpods.pro" }
        if name.contains("airpods") { return "airpods" }
        if name.contains("beats") { return "beats.headphones" }
        switch device.deviceClassMajor {
        case UInt32(kBluetoothDeviceClassMajorAudio): return "headphones"
        case UInt32(kBluetoothDeviceClassMajorPeripheral):
            if name.contains("keyboard") { return "keyboard" }
            if name.contains("trackpad") { return "rectangle.and.hand.point.up.left" }
            if name.contains("mouse") { return "magicmouse" }
            return "gamecontroller"
        case UInt32(kBluetoothDeviceClassMajorPhone): return "iphone"
        default: return "dot.radiowaves.left.and.right"
        }
    }
}
