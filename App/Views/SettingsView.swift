import SwiftUI
import TriviaCore

/// Impostazioni: due mondi ben distinti, come nel modello.
/// «Percezione» = preferenze personali (seguono il profilo, non toccano il
/// punteggio altrui). «Regole in solitaria» = le `ScoringRules` che in solo
/// il giocatore regola liberamente.
struct SettingsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    @State private var nickname = ""
    @State private var preferences = PlayerPreferences.default
    @State private var bonusEnabled = true
    @State private var basePoints = 100
    @State private var maxBonusPoints = 50
    @State private var windowSeconds = 30
    @State private var isLoaded = false

    private enum TimingChoice: String, CaseIterable, Identifiable {
        case standard, extended15, extended2, unlimited
        var id: String { rawValue }

        var label: String {
            switch self {
            case .standard: String(localized: "Standard")
            case .extended15: String(localized: "Esteso (×1,5)")
            case .extended2: String(localized: "Esteso (×2)")
            case .unlimited: String(localized: "Senza limiti")
            }
        }

        init(_ preference: TimingPreference) {
            switch preference {
            case .standard: self = .standard
            case .extended(let multiplier): self = multiplier >= 2 ? .extended2 : .extended15
            case .unlimited: self = .unlimited
            }
        }

        var preference: TimingPreference {
            switch self {
            case .standard: .standard
            case .extended15: .extended(multiplier: 1.5)
            case .extended2: .extended(multiplier: 2)
            case .unlimited: .unlimited
            }
        }
    }

    @State private var timingChoice = TimingChoice.standard

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nickname", text: $nickname)
                        .accessibilityLabel(Text("Nickname"))
                } header: {
                    Text("Profilo")
                } footer: {
                    Text("Cambiare nome non tocca punteggi, storico né power-up.")
                }

                Section("Suoni") {
                    Toggle("Effetti sonori", isOn: $preferences.audio.isEnabled)
                    if preferences.audio.isEnabled {
                        Slider(value: $preferences.audio.effectsVolume, in: 0...1) {
                            Text("Volume effetti")
                        }
                        .accessibilityValue(Text("\(Int((preferences.audio.effectsVolume * 100).rounded())) per cento"))
                    }
                }

                Section {
                    Toggle("Vibrazione", isOn: $preferences.haptics.isEnabled)
                    if preferences.haptics.isEnabled {
                        Slider(value: $preferences.haptics.intensity, in: 0...1) {
                            Text("Intensità vibrazione")
                        }
                        .accessibilityValue(Text("\(Int((preferences.haptics.intensity * 100).rounded())) per cento"))
                    }
                } header: {
                    Text("Aptica")
                } footer: {
                    Text("Il feedback dell'errore resta in ogni caso morbido.")
                }

                Section("Vista") {
                    Picker("Palette colori", selection: $preferences.visual.palette) {
                        ForEach(ColorPaletteOption.allCases, id: \.self) { palette in
                            Text(paletteName(palette)).tag(palette)
                        }
                    }
                    Toggle("Alto contrasto dell'app", isOn: $preferences.visual.prefersHighContrast)
                    Toggle("Riduci effetti luminosi", isOn: $preferences.visual.reducesEffects)
                }

                Section {
                    Picker("Tempi di risposta", selection: $timingChoice) {
                        ForEach(TimingChoice.allCases) { choice in
                            Text(choice.label).tag(choice)
                        }
                    }
                    Toggle("Leggi le domande a voce", isOn: $preferences.speech.autoReadsQuestions)
                } header: {
                    Text("Tempi e lettura")
                } footer: {
                    Text("Con tempi senza limiti il bonus velocità non si applica: conta solo la correttezza.")
                }

                Section {
                    Stepper("Punti per risposta esatta: \(basePoints)", value: $basePoints, in: 10...500, step: 10)
                    Toggle("Bonus velocità", isOn: $bonusEnabled)
                    if bonusEnabled {
                        Stepper("Bonus massimo: \(maxBonusPoints)", value: $maxBonusPoints, in: 10...200, step: 10)
                        Stepper("Finestra di risposta: \(windowSeconds) secondi", value: $windowSeconds, in: 10...120, step: 5)
                    }
                } header: {
                    Text("Regole della partita in solitaria")
                } footer: {
                    Text("In solitaria le regole sono tue. Nelle partite con altri varranno quelle comuni della partita.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle(Text("Impostazioni"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine") {
                        apply()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                guard !isLoaded else { return }
                load()
                isLoaded = true
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 560)
        #endif
    }

    private func paletteName(_ palette: ColorPaletteOption) -> String {
        switch palette {
        case .classicBlue: String(localized: "Blu classica")
        case .highContrast: String(localized: "Alto contrasto")
        case .deuteranopiaFriendly: String(localized: "Per deuteranopia")
        case .tritanopiaFriendly: String(localized: "Per tritanopia")
        case .monochrome: String(localized: "Monocromatica")
        }
    }

    private func load() {
        nickname = appModel.activeProfile.nickname
        preferences = appModel.activeProfile.preferences
        timingChoice = TimingChoice(preferences.timing)

        let rules = appModel.soloRules
        basePoints = rules.basePointsPerCorrectAnswer
        windowSeconds = Int(rules.referenceWindow.seconds)
        switch rules.speedBonus {
        case .none:
            bonusEnabled = false
        case .curve(_, let maxPoints):
            bonusEnabled = true
            maxBonusPoints = maxPoints
        }
    }

    private func apply() {
        preferences.timing = timingChoice.preference

        var profile = appModel.activeProfile
        let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            profile.nickname = trimmed
        }
        profile.preferences = preferences

        appModel.soloRules = ScoringRules(
            basePointsPerCorrectAnswer: basePoints,
            speedBonus: bonusEnabled ? .curve(.default, maxBonusPoints: maxBonusPoints) : .none,
            referenceWindow: .seconds(windowSeconds)
        )

        Task {
            await appModel.update(profile)
        }
    }
}
