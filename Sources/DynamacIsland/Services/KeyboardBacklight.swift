import Foundation

/// Built-in keyboard backlight through the private CoreBrightness framework (loaded lazily).
/// There is no public API; the class and selectors may change in a future macOS release.
enum KeyboardBacklight {
    private typealias GetFn = @convention(c) (AnyObject, Selector, UInt64) -> Float
    private typealias SetFn = @convention(c) (AnyObject, Selector, Float, UInt64) -> UInt8

    private static let getSelector = NSSelectorFromString("brightnessForKeyboard:")
    private static let setSelector = NSSelectorFromString("setBrightness:forKeyboard:")
    private static let idsSelector = NSSelectorFromString("copyKeyboardBacklightIDs")

    private static let client: NSObject? = {
        _ = dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY)
        guard let type = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type else { return nil }
        let object = type.init()
        guard object.responds(to: getSelector), object.responds(to: setSelector) else { return nil }
        return object
    }()

    private static let keyboardID: UInt64? = {
        guard let client, client.responds(to: idsSelector) else { return nil }
        let ids = client.perform(idsSelector)?.takeRetainedValue() as? [NSNumber]
        return ids?.first?.uint64Value
    }()

    static var isAvailable: Bool { client != nil && keyboardID != nil }

    /// Current brightness, 0…1.
    static var level: Float? {
        guard let client, let keyboardID else { return nil }
        let imp = class_getMethodImplementation(type(of: client), getSelector)
        return unsafeBitCast(imp, to: GetFn.self)(client, getSelector, keyboardID)
    }

    @discardableResult
    static func set(_ value: Float) -> Bool {
        guard let client, let keyboardID else { return false }
        let imp = class_getMethodImplementation(type(of: client), setSelector)
        return unsafeBitCast(imp, to: SetFn.self)(client, setSelector, min(max(value, 0), 1), keyboardID) != 0
    }
}
