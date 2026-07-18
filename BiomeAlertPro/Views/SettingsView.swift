import SwiftUI

/// All user-configurable preferences.
struct SettingsView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        SettingsContent(environment: environment)
    }
}

private struct SettingsContent: View {
    @EnvironmentObject private var environment: AppEnvironment
    @ObservedObject private var settings: SettingsStore
    @State private var launchAtLogin = LaunchAtLoginService.isEnabled
    @State private var launchAtLoginError: String?

    init(environment: AppEnvironment) {
        _settings = ObservedObject(wrappedValue: environment.settings)
    }

    var body: some View {
        Form {
            notificationsSection
            robloxSection
            biomeLaunchSection
            detectionSection
            hotkeysSection
            appearanceSection
            performanceSection
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
    }

    private var biomeLaunchSection: some View {
        Section {
            ForEach(KeywordCategory.allCases.filter(\.isBiome)) { category in
                Toggle(isOn: Binding(
                    get: { settings.isBiomeAutoLaunchEnabled(category) },
                    set: { enabled in
                        settings.setBiomeAutoLaunch(category, enabled: enabled)
                        environment.applyScreenWatcherSetting()
                    }
                )) {
                    Label {
                        HStack(spacing: 6) {
                            Text(category.displayName)
                            if category.isRare {
                                Text("RARE")
                                    .font(.caption2.weight(.bold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(.purple.opacity(0.25), in: Capsule())
                            }
                        }
                    } icon: {
                        Image(systemName: category.symbolName)
                    }
                }
            }
        } header: {
            Text("Auto-Launch Biomes")
        } footer: {
            Text("Roblox launches automatically only for links tied to the biomes selected here. Alerts with a link but no recognized biome follow the master auto-launch switch.")
        }
    }

    // MARK: - Sections

    private var notificationsSection: some View {
        Section {
            Toggle("Show desktop notifications", isOn: $settings.notificationsEnabled)
            Toggle("Play alert sound", isOn: $settings.soundEnabled)
            Picker("Alert sound", selection: $settings.alertSoundName) {
                ForEach(SoundPlayer.availableSounds, id: \.self) { sound in
                    Text(sound).tag(sound)
                }
            }
            .disabled(!settings.soundEnabled)
            .onChange(of: settings.alertSoundName) { _, newValue in
                environment.sounds.play(named: newValue)
            }

            Toggle("Use a different sound per biome", isOn: $settings.perBiomeSoundsEnabled)
                .disabled(!settings.soundEnabled)

            if settings.perBiomeSoundsEnabled {
                ForEach(KeywordCategory.allCases.filter(\.isBiome)) { category in
                    Picker(selection: Binding(
                        get: { settings.biomeSound(for: category) },
                        set: { newSound in
                            settings.setBiomeSound(newSound, for: category)
                            environment.sounds.play(named: newSound)
                        }
                    )) {
                        ForEach(SoundPlayer.availableSounds, id: \.self) { sound in
                            Text(sound).tag(sound)
                        }
                    } label: {
                        Label(category.displayName, systemImage: category.symbolName)
                    }
                    .disabled(!settings.soundEnabled)
                }
            }
        } header: {
            Text("Notifications & Sound")
        } footer: {
            if settings.perBiomeSoundsEnabled {
                Text("Each biome plays its own sound so you can tell what dropped without looking.")
            }
        }
    }

    private var robloxSection: some View {
        Section {
            Toggle("Launch Roblox automatically", isOn: $settings.autoLaunchRoblox)
            Toggle("Only launch for rare biomes", isOn: $settings.launchOnlyForRareBiomes)
                .disabled(!settings.autoLaunchRoblox)
            Toggle("Keep Roblox pre-launched while monitoring", isOn: $settings.prewarmRoblox)
                .onChange(of: settings.prewarmRoblox) { _, enabled in
                    if enabled && environment.isMonitoring {
                        environment.launcher.prewarm()
                    }
                }

            LabeledContent("Launch delay") {
                HStack {
                    Slider(value: $settings.launchDelaySeconds, in: 0...10, step: 0.5)
                        .frame(width: 180)
                    Text(String(format: "%.1f s", settings.launchDelaySeconds))
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
            }
            .disabled(!settings.autoLaunchRoblox)

            LabeledContent("Duplicate launch cooldown") {
                HStack {
                    Slider(value: $settings.launchCooldownSeconds, in: 10...600, step: 10)
                        .frame(width: 180)
                    Text(String(format: "%.0f s", settings.launchCooldownSeconds))
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
            }
        } header: {
            Text("Roblox Launch")
        } footer: {
            Text("The cooldown prevents joining the same private server repeatedly when several people share the same link.")
        }
    }

    private var detectionSection: some View {
        Section {
            LabeledContent("Confidence threshold") {
                HStack {
                    Slider(value: $settings.confidenceThreshold, in: 0.1...1.0, step: 0.05)
                        .frame(width: 180)
                    Text(String(format: "%.2f", settings.confidenceThreshold))
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
            }
            LabeledContent("Duplicate event cooldown") {
                HStack {
                    Slider(value: $settings.duplicateCooldownSeconds, in: 5...600, step: 5)
                        .frame(width: 180)
                    Text(String(format: "%.0f s", settings.duplicateCooldownSeconds))
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
            }
            LabeledContent("Dedupe cache duration") {
                HStack {
                    Slider(value: $settings.cacheDurationMinutes, in: 1...120, step: 1)
                        .frame(width: 180)
                    Text(String(format: "%.0f min", settings.cacheDurationMinutes))
                        .monospacedDigit()
                        .frame(width: 52, alignment: .trailing)
                }
            }
            Toggle("Fuzzy keyword matching", isOn: $settings.fuzzyMatchingEnabled)

            VStack(alignment: .leading, spacing: 4) {
                Label("Blocklist words", systemImage: "hand.raised.slash")
                    .font(.callout.weight(.medium))
                TextField("fake, expired, closed, patched, scam, full", text: $settings.blocklist, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
                Text("If a message contains any of these words it is ignored — so a link marked “fake” or “closed” never launches. Comma or newline separated.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Detection")
        } footer: {
            Text("Alerts fire when the combined keyword + link confidence reaches the threshold, or when a rare biome keyword is detected.")
        }
    }

    private var hotkeysSection: some View {
        Section {
            Toggle("Enable global hotkeys", isOn: $settings.globalHotkeysEnabled)
                .onChange(of: settings.globalHotkeysEnabled) { _, _ in
                    environment.applyHotkeySetting()
                }
            LabeledContent("Join last detected link", value: HotKeyService.joinLastDescription)
            LabeledContent("Pause / resume monitoring", value: HotKeyService.togglePauseDescription)
            LabeledContent("Click newest Join button now", value: HotKeyService.clickNewestDescription)
        } header: {
            Text("Hotkeys")
        } footer: {
            Text("System-wide shortcuts that work even while Discord or Roblox is focused. ⌥ is Option, ⌘ is Command.")
        }
    }

    private var appearanceSection: some View {
        Section {
            Picker("Theme", selection: $settings.theme) {
                ForEach(AppTheme.allCases) { theme in
                    Text(theme.displayName).tag(theme)
                }
            }
            .pickerStyle(.segmented)

            Toggle("Show menu bar icon", isOn: $settings.menuBarEnabled)
                .onChange(of: settings.menuBarEnabled) { _, enabled in
                    // Never allow hiding both the Dock icon and the menu bar icon.
                    if !enabled && settings.menuBarOnly {
                        settings.menuBarOnly = false
                    }
                }
            Toggle("Menu bar only (hide Dock icon)", isOn: $settings.menuBarOnly)
                .disabled(!settings.menuBarEnabled)

            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    guard newValue != LaunchAtLoginService.isEnabled else { return }
                    do {
                        try LaunchAtLoginService.setEnabled(newValue)
                        launchAtLoginError = nil
                        environment.logs.log(.info, .lifecycle, "Launch at login \(newValue ? "enabled" : "disabled")")
                    } catch {
                        launchAtLoginError = error.localizedDescription
                        launchAtLogin = LaunchAtLoginService.isEnabled
                    }
                }
            if let launchAtLoginError {
                Text(launchAtLoginError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Appearance & Behavior")
        }
    }

    private var performanceSection: some View {
        Section {
            LabeledContent("CPU usage target") {
                HStack {
                    Slider(value: $settings.cpuLimitPercent, in: 0.5...10, step: 0.5)
                        .frame(width: 180)
                    Text(String(format: "%.1f%%", settings.cpuLimitPercent))
                        .monospacedDigit()
                        .frame(width: 48, alignment: .trailing)
                }
            }
            .onChange(of: settings.cpuLimitPercent) { _, newValue in
                environment.performance.cpuLimitPercent = newValue
            }

            Picker("Logging level", selection: $settings.loggingLevel) {
                ForEach(LogLevel.allCases) { level in
                    Text(level.displayName).tag(level)
                }
            }
            .onChange(of: settings.loggingLevel) { _, newValue in
                environment.logs.minimumLevel = newValue
            }

            LabeledContent("History limit") {
                TextField("", value: $settings.historyLimit, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                    .onChange(of: settings.historyLimit) { _, newValue in
                        environment.history.limit = max(100, newValue)
                    }
            }
        } header: {
            Text("Performance & Logging")
        } footer: {
            Text("Exceeding the CPU target raises a warning in the logs and on the dashboard — useful for verifying the app stays lightweight over long sessions.")
        }
    }
}
