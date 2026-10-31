import AppKit
import AudioToolbox
import CoreAudio

enum MediaKey: Int32 {
    case soundUp = 0, soundDown = 1, brightnessUp = 2, brightnessDown = 3, mute = 7
}

/// Intercepts volume/brightness keys with a CGEventTap so the island can replace the system HUD.
/// The tap only listens to NX_SYSDEFINED events, so it costs nothing while keys aren't pressed.
@MainActor
final class MediaKeyService {
    /// Return true to swallow the event (we handled it), false to let the system handle it.
    var handler: ((MediaKey, _ isDown: Bool, _ fineStep: Bool) -> Bool)?
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var isRunning: Bool { tap != nil }

    static func isTrusted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        guard Self.isTrusted(prompt: false) else { return false }
        let mask = CGEventMask(1 << 14) // NX_SYSDEFINED
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let service = Unmanaged<MediaKeyService>.fromOpaque(refcon).takeUnretainedValue()
                return MainActor.assumeIsolated { service.handle(type: type, event: event) }
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        tap = nil
        runLoopSource = nil
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        }
        guard type.rawValue == 14, let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == 8 else { return pass }
        let code = Int32((ns.data1 & 0xFFFF_0000) >> 16)
        let isDown = ((ns.data1 & 0xFF00) >> 8) == 0xA
        guard let key = MediaKey(rawValue: code), let handler else { return pass }
        let fine = ns.modifierFlags.contains([.option, .shift])
        return handler(key, isDown, fine) ? nil : pass
    }
}

enum VolumeControl {
    private static func defaultDevice() -> AudioDeviceID? {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return status == noErr && id != 0 ? id : nil
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    static var isAvailable: Bool {
        guard let device = defaultDevice() else { return false }
        var addr = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        var settable: DarwinBoolean = false
        return AudioObjectHasProperty(device, &addr)
            && AudioObjectIsPropertySettable(device, &addr, &settable) == noErr && settable.boolValue
    }

    static var volume: Float {
        get {
            guard let device = defaultDevice() else { return 0 }
            var addr = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
            var value = Float32(0)
            var size = UInt32(MemoryLayout<Float32>.size)
            AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value)
            return value
        }
        set {
            guard let device = defaultDevice() else { return }
            var addr = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
            var value = Float32(min(max(newValue, 0), 1))
            AudioObjectSetPropertyData(device, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
        }
    }

    static var isMuted: Bool {
        get {
            guard let device = defaultDevice() else { return false }
            var addr = address(kAudioDevicePropertyMute)
            guard AudioObjectHasProperty(device, &addr) else { return false }
            var value = UInt32(0)
            var size = UInt32(MemoryLayout<UInt32>.size)
            AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value)
            return value != 0
        }
        set {
            guard let device = defaultDevice() else { return }
            var addr = address(kAudioDevicePropertyMute)
            guard AudioObjectHasProperty(device, &addr) else { return }
            var value = UInt32(newValue ? 1 : 0)
            AudioObjectSetPropertyData(device, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
        }
    }
}

/// Built-in display brightness through the private DisplayServices framework (loaded lazily).
enum BrightnessControl {
    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private static let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
    private static let getFn: GetFn? = handle.flatMap { dlsym($0, "DisplayServicesGetBrightness") }.map { unsafeBitCast($0, to: GetFn.self) }
    private static let setFn: SetFn? = handle.flatMap { dlsym($0, "DisplayServicesSetBrightness") }.map { unsafeBitCast($0, to: SetFn.self) }

    private static var display: CGDirectDisplayID {
        var count: UInt32 = 0
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        CGGetActiveDisplayList(16, &ids, &count)
        return ids.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 } ?? CGMainDisplayID()
    }

    static var brightness: Float? {
        guard let getFn else { return nil }
        var value: Float = 0
        return getFn(display, &value) == 0 ? value : nil
    }

    static func set(_ value: Float) -> Bool {
        guard let setFn else { return false }
        return setFn(display, min(max(value, 0), 1)) == 0
    }
}
