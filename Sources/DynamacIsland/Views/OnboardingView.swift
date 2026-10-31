import AppKit
import CoreBluetooth
import EventKit
import SwiftUI

/// Live permission status for the onboarding checklist. Polls only while the onboarding window is open.
@MainActor
final class PermissionStatus: ObservableObject {
    enum State { case granted, needed, optional }

    @Published private(set) var accessibility = State.needed
    @Published private(set) var calendar = State.needed
    @Published private(set) var automation = State.optional
    @Published private(set) var bluetooth = State.optional
    @Published private(set) var fullDiskAccess = State.optional
    private var timer: Timer?

    func startRefreshing() {
        refresh()
        timer?.invalidate()
        let t = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stopRefreshing() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        accessibility = MediaKeyService.isTrusted(prompt: false) ? .granted : .needed
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .authorized: calendar = .granted
        default: calendar = .needed
        }
        bluetooth = CBManager.authorization == .allowedAlways ? .granted : .optional
        fullDiskAccess = FocusMonitor.hasAccess ? .granted : .optional
        Task.detached(priority: .utility) {
            let granted = ["com.apple.Music", "com.spotify.client"].contains { Self.automationStatus($0, ask: false) == noErr }
            await MainActor.run { self.automation = granted ? .granted : .optional }
        }
    }

    nonisolated static func automationStatus(_ bundleID: String, ask: Bool) -> OSStatus {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
        return AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, ask)
    }

    func requestAutomation() {
        Task.detached(priority: .userInitiated) {
            for id in ["com.spotify.client", "com.apple.Music"]
            where !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty {
                _ = Self.automationStatus(id, ask: true)
            }
            await MainActor.run { self.refresh() }
        }
    }
}

struct OnboardingView: View {
    @ObservedObject var status: PermissionStatus
    let calendar: CalendarService
    let requestBluetooth: () -> Void
    let finish: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                BlackHoleIcon(size: 96, spinning: true)
                Text("Welcome to Dynamac Island").font(.system(size: 22, weight: .bold))
                Text("Grant what you'd like to use. Everything else keeps working without it.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            VStack(spacing: 10) {
                row("keyboard", "Accessibility", "Volume & brightness HUD, media keys", status.accessibility) {
                    _ = MediaKeyService.isTrusted(prompt: true)
                }
                row("calendar", "Calendar", "Upcoming events and time-to-leave alerts", status.calendar) {
                    calendar.access == .denied ? calendar.openPrivacySettings() : calendar.requestAccess()
                }
                row("music.note", "Automation", "Shuffle, repeat, favorite & links for Music/Spotify", status.automation) {
                    status.requestAutomation()
                }
                row("airpods", "Bluetooth", "AirPods & device connection activity", status.bluetooth, action: requestBluetooth)
                row("moon.fill", "Full Disk Access", "Show Focus mode changes (reads the Focus database)", status.fullDiskAccess) {
                    FocusMonitor.openFullDiskAccessSettings()
                }
            }
            Button(action: finish) {
                Text("Done").frame(width: 120)
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.large)
        }
        .padding(28)
        .frame(width: 520)
        .onAppear { status.startRefreshing() }
        .onDisappear { status.stopRefreshing() }
    }

    private func row(_ symbol: String, _ title: String, _ detail: String, _ state: PermissionStatus.State,
                     action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 16, weight: .semibold)).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            if state == .granted {
                Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.system(size: 12, weight: .semibold))
            } else {
                Button(state == .needed ? "Grant…" : "Enable…", action: action)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.05)))
    }
}
