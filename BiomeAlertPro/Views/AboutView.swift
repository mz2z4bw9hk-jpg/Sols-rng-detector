import SwiftUI

struct AboutView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 96, height: 96)
                    .shadow(radius: 8)

                VStack(spacing: 4) {
                    Text("Biome Alert Pro")
                        .font(.largeTitle.weight(.bold))
                    Text("Version \(environment.appVersion)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Text("A lightweight desktop companion for Sol's RNG players. Receives biome alerts through officially supported Discord integrations, detects rare biomes with an intelligent keyword engine, and launches Roblox the moment a private server link arrives.")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 480)

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Uses only official Discord authentication and APIs — OAuth2, incoming webhooks, and the bot Gateway.", systemImage: "checkmark.seal")
                        Label("No user tokens, no self-botting, no reverse-engineered endpoints.", systemImage: "hand.raised")
                        Label("Secrets are stored in the macOS Keychain and never logged.", systemImage: "lock.shield")
                        Label("Sandboxed, Hardened Runtime, 100% native Swift 6 + SwiftUI.", systemImage: "swift")
                    }
                    .font(.callout)
                    .padding(6)
                }
                .frame(maxWidth: 520)

                Text("Biome Alert Pro is a fan-made utility and is not affiliated with Discord Inc., Roblox Corporation, or the creators of Sol's RNG.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 480)
            }
            .padding(32)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("About")
    }
}
