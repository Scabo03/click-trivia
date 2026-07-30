import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Fotografia osservabile delle impostazioni di accessibilità di sistema,
/// per i livelli **non-View** (FeedbackCenter, motore di gioco, audio).
///
/// Nelle viste SwiftUI si usano invece i valori d'ambiente nativi
/// (`\.accessibilityReduceMotion`, `\.accessibilityDifferentiateWithoutColor`,
/// `\.legibilityWeight`, Dynamic Type, ecc.), che restano la fonte primaria
/// per il layout.
@MainActor
@Observable
public final class SystemAccessibilitySettings {
    public private(set) var isVoiceOverRunning = false
    public private(set) var prefersReducedMotion = false
    public private(set) var prefersIncreasedContrast = false
    public private(set) var prefersReducedTransparency = false
    public private(set) var shouldDifferentiateWithoutColor = false
    public private(set) var isBoldTextEnabled = false

    // Fuori dall'osservazione e dall'isolamento: il deinit non è isolato al
    // MainActor e NotificationCenter.removeObserver è thread-safe.
    @ObservationIgnored nonisolated(unsafe) private var observers: [any NSObjectProtocol] = []

    public init() {
        refresh()
        startObserving()
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func refresh() {
        #if canImport(UIKit)
        isVoiceOverRunning = UIAccessibility.isVoiceOverRunning
        prefersReducedMotion = UIAccessibility.isReduceMotionEnabled
        prefersIncreasedContrast = UIAccessibility.isDarkerSystemColorsEnabled
        prefersReducedTransparency = UIAccessibility.isReduceTransparencyEnabled
        shouldDifferentiateWithoutColor = UIAccessibility.shouldDifferentiateWithoutColor
        isBoldTextEnabled = UIAccessibility.isBoldTextEnabled
        #elseif canImport(AppKit)
        let workspace = NSWorkspace.shared
        isVoiceOverRunning = workspace.isVoiceOverEnabled
        prefersReducedMotion = workspace.accessibilityDisplayShouldReduceMotion
        prefersIncreasedContrast = workspace.accessibilityDisplayShouldIncreaseContrast
        prefersReducedTransparency = workspace.accessibilityDisplayShouldReduceTransparency
        shouldDifferentiateWithoutColor = workspace.accessibilityDisplayShouldDifferentiateWithoutColor
        // Bold Text non esiste come impostazione macOS: resta false.
        isBoldTextEnabled = false
        #endif
    }

    private func startObserving() {
        #if canImport(UIKit)
        let names: [Notification.Name] = [
            UIAccessibility.voiceOverStatusDidChangeNotification,
            UIAccessibility.reduceMotionStatusDidChangeNotification,
            UIAccessibility.darkerSystemColorsStatusDidChangeNotification,
            UIAccessibility.reduceTransparencyStatusDidChangeNotification,
            UIAccessibility.differentiateWithoutColorDidChangeNotification,
            UIAccessibility.boldTextStatusDidChangeNotification,
        ]
        #elseif canImport(AppKit)
        let names: [Notification.Name] = [
            NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
        ]
        #else
        let names: [Notification.Name] = []
        #endif

        for name in names {
            let observer = NotificationCenter.default.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.refresh()
                }
            }
            observers.append(observer)
        }
    }
}
