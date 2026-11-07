import Foundation

/// Built-in keyboard backlight through the private CoreBrightness framework (loaded lazily).
/// There is no public API; the class and selectors may change in a future macOS release.
enum KeyboardBacklight {
    private typealias GetFn = @convention(c) (AnyObject, Selector, UInt64) -> Float
    private typealias SetFn = @convention(c) (AnyObject, Selector, Float, UInt64) -> UInt8
    private typealias BoolGetFn = @convention(c) (AnyObject, Selector, UInt64) -> UInt8
    private typealias BoolSetFn = @convention(c) (AnyObject, Selector, UInt8, UInt64) -> UInt8

    private static let getSelector = NSSelectorFromString("brightnessForKeyboard:")
    private static let setSelector = NSSelectorFromString("setBrightness:forKeyboard:")
    private static let idsSelector = NSSelectorFromString("copyKeyboardBacklightIDs")
    private static let autoGetSelector = NSSelectorFromString("isAutoBrightnessEnabledForKeyboard:")
    private static let autoSetSelector = NSSelectorFromString("enableAutoBrightness:forKeyboard:")

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

    /// macOS "Adjust keyboard brightness in low light": while on, the ambient light sensor overrides manual levels.
    static var isAutoEnabled: Bool {
        guard let client, let keyboardID, client.responds(to: autoGetSelector) else { return false }
        let imp = class_getMethodImplementation(type(of: client), autoGetSelector)
        return unsafeBitCast(imp, to: BoolGetFn.self)(client, autoGetSelector, keyboardID) != 0
    }

    @discardableResult
    static func setAuto(_ enabled: Bool) -> Bool {
        guard let client, let keyboardID, client.responds(to: autoSetSelector) else { return false }
        let imp = class_getMethodImplementation(type(of: client), autoSetSelector)
        return unsafeBitCast(imp, to: BoolSetFn.self)(client, autoSetSelector, enabled ? 1 : 0, keyboardID) != 0
    }

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
