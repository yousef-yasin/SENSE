import SwiftData
import SwiftUI

@main
struct SENSEApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .modelContainer(app.container)
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if app.settings.hasCompletedOnboarding {
                HomeView()
            } else {
                OnboardingView()
            }
        }
        .task {
            await app.permissions.refresh()
            await app.reminders.syncDelivered()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await app.permissions.refresh()
                await app.reminders.syncDelivered()
            }
        }
        .alert(
            String(localized: "Storage unavailable"),
            isPresented: Binding(get: { app.storageError != nil }, set: { if !$0 { app.dismissStorageError() } })
        ) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(app.storageError?.localizedDescription ?? "")
        }
    }
}
