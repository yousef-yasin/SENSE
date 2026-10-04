import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: "SENSE")
                        .font(.system(.largeTitle, design: .rounded, weight: .heavy))
                        .tracking(4)
                    Text("AI that understands the world around you.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 48)

                VStack(alignment: .leading, spacing: 24) {
                    feature(
                        symbol: "viewfinder",
                        title: String(localized: "Capture anything"),
                        detail: String(localized: "Point your camera, pick a photo, speak, or type. No folders, no tagging.")
                    )
                    feature(
                        symbol: "sparkles",
                        title: String(localized: "SENSE understands it"),
                        detail: String(localized: "Deadlines, dates, amounts, warnings and requirements are pulled out for you, with reminders one tap away.")
                    )
                    feature(
                        symbol: "brain.head.profile",
                        title: String(localized: "Remember and recall"),
                        detail: String(localized: "Ask things like “What did I capture at the university yesterday?” and find it again.")
                    )
                    feature(
                        symbol: "lock.shield",
                        title: String(localized: "Private by design"),
                        detail: String(localized: "Understanding happens on this iPhone. SENSE asks before using the camera, microphone or location, and only while you're using them. Nothing leaves your device unless you connect your own AI provider.")
                    )
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                app.settings.hasCompletedOnboarding = true
            } label: {
                Text("Get Started")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
            .background(.bar)
        }
    }

    private func feature(symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 36)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
