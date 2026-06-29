import SwiftUI

@main
struct ChurchServiceSchedulerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = SchedulerStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            LockGateView()
                .environmentObject(store)
                .onAppear {
                    BackgroundReminderManager.shared.configure(store: store)
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .background {
                        BackgroundReminderManager.shared.scheduleNextReminder(from: store.data.reminders)
                    }
                }
        }
    }
}
