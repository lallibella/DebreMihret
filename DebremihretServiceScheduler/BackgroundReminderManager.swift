import BackgroundTasks
import Foundation
import UIKit

@MainActor
final class BackgroundReminderManager {
    static let shared = BackgroundReminderManager()

    private let taskIdentifier = "com.church.servicescheduler.telegramReminder"
    private weak var store: SchedulerStore?
    private var registered = false

    private init() {}

    func configure(store: SchedulerStore) {
        self.store = store
        scheduleNextReminder(from: store.data.reminders)
    }

    func register() {
        guard !registered else { return }
        registered = true

        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            Task { @MainActor in
                self.handle(task)
            }
        }
    }

    func scheduleNextReminder(from reminders: [Reminder]) {
        guard let next = reminders
            .filter({ $0.status != .sent })
            .sorted(by: { $0.scheduledAt < $1.scheduledAt })
            .first else {
            return
        }

        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = next.scheduledAt
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            let prefix = store?.localized("Background reminder scheduling failed") ?? "Background reminder scheduling failed"
            store?.errorMessage = "\(prefix): \(error.localizedDescription)"
        }
    }

    func scheduleCurrentStore() {
        scheduleNextReminder(from: store?.data.reminders ?? [])
    }

    private func handle(_ task: BGTask) {
        scheduleNextReminder(from: store?.data.reminders ?? [])

        let work = Task { @MainActor in
            await store?.sendDueReminders()
            task.setTaskCompleted(success: true)
            scheduleNextReminder(from: store?.data.reminders ?? [])
        }

        task.expirationHandler = {
            work.cancel()
            task.setTaskCompleted(success: false)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        BackgroundReminderManager.shared.register()
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        BackgroundReminderManager.shared.scheduleCurrentStore()
    }
}
