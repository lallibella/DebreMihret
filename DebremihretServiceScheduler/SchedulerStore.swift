import Foundation

@MainActor
final class SchedulerStore: ObservableObject {
    @Published private(set) var data: AppData
    @Published var noticeMessage: String?
    @Published var errorMessage: String?

    private let storage = EncryptedDataStore()
    private let telegram = TelegramClient()

    init() {
        do {
            self.data = try storage.load()
            migrateTaskCatalogIfNeeded()
        } catch {
            self.data = .seed
            self.errorMessage = error.localizedDescription
        }
    }

    var linkedServantCount: Int {
        data.servants.filter(\.isTelegramLinked).count
    }

    var pendingReminderCount: Int {
        data.reminders.filter { $0.status != .sent }.count
    }

    var nextPendingReminder: Reminder? {
        data.reminders
            .filter { $0.status != .sent }
            .sorted { $0.scheduledAt < $1.scheduledAt }
            .first
    }

    var language: AppLanguage {
        data.settings.language
    }

    func localized(_ key: String) -> String {
        language.text(key)
    }

    func servant(id: UUID?) -> Servant? {
        guard let id else { return nil }
        return data.servants.first { $0.id == id }
    }

    func task(id: UUID) -> TaskTemplate? {
        data.tasks.first { $0.id == id }
    }

    func schedule(id: UUID) -> Schedule? {
        data.schedules.first { $0.id == id }
    }

    func upsertServant(_ servant: Servant) {
        if let index = data.servants.firstIndex(where: { $0.id == servant.id }) {
            data.servants[index] = servant
        } else {
            data.servants.append(servant)
        }

        for scheduleIndex in data.schedules.indices {
            for assignmentIndex in data.schedules[scheduleIndex].assignments.indices {
                if data.schedules[scheduleIndex].assignments[assignmentIndex].servantID == servant.id {
                    data.schedules[scheduleIndex].assignments[assignmentIndex].servantName = servant.name
                }
            }
        }
        persist(success: localized("Servant saved."))
    }

    func deleteServants(at offsets: IndexSet) {
        let servants = offsets.map { data.servants[$0] }
        servants.forEach { deleteServant(id: $0.id, showNotice: false) }
        persist(success: localized("Servant deleted."))
    }

    func deleteServant(id: UUID, showNotice: Bool = true) {
        data.servants.removeAll { $0.id == id }
        for scheduleIndex in data.schedules.indices {
            for assignmentIndex in data.schedules[scheduleIndex].assignments.indices {
                if data.schedules[scheduleIndex].assignments[assignmentIndex].servantID == id {
                    data.schedules[scheduleIndex].assignments[assignmentIndex].servantID = nil
                    data.schedules[scheduleIndex].assignments[assignmentIndex].servantName = nil
                }
            }
        }
        data.reminders.removeAll { $0.servantID == id }
        persist(success: showNotice ? localized("Servant deleted.") : nil)
    }

    func upsertTask(_ task: TaskTemplate) {
        let normalized = TaskTemplate(
            id: task.id,
            name: task.name.trimmingCharacters(in: .whitespacesAndNewlines),
            requiredPeople: task.requiredPeople,
            kind: task.kind,
            qualifiedRoles: task.qualifiedRoles.uniqued()
        )
        if let index = data.tasks.firstIndex(where: { $0.id == normalized.id }) {
            data.tasks[index] = normalized
        } else {
            data.tasks.append(normalized)
        }

        for scheduleIndex in data.schedules.indices {
            for assignmentIndex in data.schedules[scheduleIndex].assignments.indices {
                if data.schedules[scheduleIndex].assignments[assignmentIndex].taskID == normalized.id {
                    data.schedules[scheduleIndex].assignments[assignmentIndex].taskName = normalized.name
                    data.schedules[scheduleIndex].assignments[assignmentIndex].qualifiedRoles = normalized.qualifiedRoles
                }
            }
        }
        persist(success: localized("Task saved."))
    }

    func deleteTasks(at offsets: IndexSet) {
        let tasks = offsets.map { data.tasks[$0] }
        let ids = Set(tasks.map(\.id))
        let assignmentIDs = Set(
            data.schedules.flatMap { schedule in
                schedule.assignments
                    .filter { ids.contains($0.taskID) }
                    .map(\.id)
            }
        )
        data.tasks.removeAll { ids.contains($0.id) }
        for scheduleIndex in data.schedules.indices {
            data.schedules[scheduleIndex].assignments.removeAll { ids.contains($0.taskID) }
        }
        data.reminders.removeAll { assignmentIDs.contains($0.assignmentID) }
        persist(success: localized("Task deleted."))
    }

    func generateWeeklySchedule() {
        let startsAt = Date.nextRecurringServiceDate(days: data.settings.recurringServiceDays)
        let recurringTasks = data.tasks
            .filter { $0.kind == .recurringSunday }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        guard !recurringTasks.isEmpty else {
            errorMessage = localized("Add at least one recurring weekly task first.")
            return
        }

        var alreadyAssigned = Set<UUID>()
        var assignments: [Assignment] = []
        let history = assignmentHistory(before: startsAt)

        for task in recurringTasks {
            for _ in 0..<max(1, task.requiredPeople) {
                let chosen = bestServant(for: task, alreadyAssigned: alreadyAssigned, history: history)
                if let chosen {
                    alreadyAssigned.insert(chosen.id)
                }
                assignments.append(
                    Assignment(
                        taskID: task.id,
                        taskName: task.name,
                        qualifiedRoles: task.qualifiedRoles,
                        servantID: chosen?.id,
                        servantName: chosen?.name
                    )
                )
            }
        }

        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEEE"
        let scheduleTitle = "\(dayFormatter.string(from: startsAt)) Service"

        let schedule = Schedule(
            title: scheduleTitle,
            startsAt: startsAt,
            kind: .recurringSunday,
            assignments: assignments
        )
        data.schedules.append(schedule)
        data.schedules.sort { $0.startsAt < $1.startsAt }
        persist(success: language.weeklyScheduleGenerated(for: startsAt))
    }

    func createCustomSchedule(title: String, startsAt: Date, taskIDs: Set<UUID>) {
        let selectedTasks = data.tasks
            .filter { taskIDs.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = localized("Enter an event title.")
            return
        }
        guard startsAt > Date() else {
            errorMessage = localized("Choose a future event date.")
            return
        }
        guard !selectedTasks.isEmpty else {
            errorMessage = localized("Select at least one task for the occasion.")
            return
        }

        var assignments: [Assignment] = []
        for task in selectedTasks {
            for _ in 0..<max(1, task.requiredPeople) {
                assignments.append(
                    Assignment(
                        taskID: task.id,
                        taskName: task.name,
                        qualifiedRoles: task.qualifiedRoles
                    )
                )
            }
        }

        data.schedules.append(
            Schedule(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                startsAt: startsAt,
                kind: .customOccasion,
                assignments: assignments
            )
        )
        data.schedules.sort { $0.startsAt < $1.startsAt }
        persist(success: localized("Custom occasion created."))
    }

    func deleteSchedule(id: UUID) {
        data.schedules.removeAll { $0.id == id }
        data.reminders.removeAll { $0.scheduleID == id }
        persist(success: localized("Schedule deleted."))
    }

    func setAssignmentServant(scheduleID: UUID, assignmentID: UUID, servantID: UUID?) {
        guard let scheduleIndex = data.schedules.firstIndex(where: { $0.id == scheduleID }),
              let assignmentIndex = data.schedules[scheduleIndex].assignments.firstIndex(where: { $0.id == assignmentID }) else {
            return
        }

        let servant = servant(id: servantID)
        data.schedules[scheduleIndex].assignments[assignmentIndex].servantID = servant?.id
        data.schedules[scheduleIndex].assignments[assignmentIndex].servantName = servant?.name

        if data.schedules[scheduleIndex].isFinalized {
            rebuildReminders(forScheduleAt: scheduleIndex)
        }
        persist(success: localized("Assignment updated."))
    }

    func finalizeSchedule(id: UUID) {
        guard let scheduleIndex = data.schedules.firstIndex(where: { $0.id == id }) else { return }
        data.schedules[scheduleIndex].finalizedAt = Date()
        rebuildReminders(forScheduleAt: scheduleIndex)
        persist(success: localized("Schedule finalized and reminders prepared."))
    }

    func eligibleServants(for assignment: Assignment) -> [Servant] {
        let eligible = data.servants.filter { isServant($0, qualifiedFor: assignment.qualifiedRoles) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let ineligible = data.servants.filter { !isServant($0, qualifiedFor: assignment.qualifiedRoles) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return eligible + ineligible
    }

    func linkURL(for servant: Servant) -> URL? {
        let username = data.settings.botUsername
            .trimmingCharacters(in: CharacterSet(charactersIn: "@ ").union(.whitespacesAndNewlines))
        guard !username.isEmpty else { return nil }
        return URL(string: "https://t.me/\(username)?start=\(servant.id.uuidString)")
    }

    func updateSettings(_ transform: (inout AppSettings) -> Void) {
        transform(&data.settings)
        persist()
    }

    @discardableResult
    func setPIN(_ pin: String) -> Bool {
        let trimmed = pin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 4, trimmed.allSatisfy(\.isNumber) else {
            errorMessage = localized("Use a 4-digit PIN.")
            return false
        }

        do {
            let salt = try PINHasher.makeSalt()
            data.settings.pinSalt = salt
            data.settings.pinHash = PINHasher.hash(pin: trimmed, salt: salt)
            data.settings.appLockEnabled = true
            data.settings.securitySetupCompleted = true
            persist(success: localized("App lock PIN saved."))
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func verifyPIN(_ pin: String) -> Bool {
        guard let salt = data.settings.pinSalt, let hash = data.settings.pinHash else {
            return false
        }
        return PINHasher.hash(pin: pin.trimmingCharacters(in: .whitespacesAndNewlines), salt: salt) == hash
    }

    func exportBackup(password: String) throws -> Data {
        try storage.exportBackup(data: data, password: password)
    }

    func importBackup(_ backup: Data, password: String) {
        do {
            let localSecurity = (
                appLockEnabled: data.settings.appLockEnabled,
                securitySetupCompleted: data.settings.securitySetupCompleted,
                pinSalt: data.settings.pinSalt,
                pinHash: data.settings.pinHash
            )
            data = try storage.importBackup(backup, password: password)
            data.settings.appLockEnabled = localSecurity.appLockEnabled
            data.settings.securitySetupCompleted = localSecurity.securitySetupCompleted
            data.settings.pinSalt = localSecurity.pinSalt
            data.settings.pinHash = localSecurity.pinHash
            persist(success: localized("Backup imported."))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func syncTelegramLinks() async {
        do {
            let updates = try await telegram.getUpdates(
                token: data.settings.botToken,
                offset: data.settings.telegramUpdateOffset
            )
            var linked = 0
            var nextOffset = data.settings.telegramUpdateOffset

            for update in updates {
                nextOffset = max(nextOffset, update.updateID + 1)
                guard let payload = update.startPayload,
                      let servantID = UUID(uuidString: payload),
                      let chatID = update.message?.chat.id,
                      let index = data.servants.firstIndex(where: { $0.id == servantID }) else {
                    continue
                }

                data.servants[index].telegramChatID = String(chatID)
                linked += 1
            }

            data.settings.telegramUpdateOffset = nextOffset
            persist(success: language.linkedServants(linked))
        } catch {
            errorMessage = localized(error.localizedDescription)
        }
    }

    func sendDueReminders(now: Date = Date()) async {
        let dueIDs = data.reminders
            .filter { $0.status != .sent && $0.scheduledAt <= now }
            .map(\.id)

        guard !dueIDs.isEmpty else {
            noticeMessage = localized("No reminders are due right now.")
            return
        }

        var sent = 0
        var failed = 0

        for reminderID in dueIDs {
            guard let index = data.reminders.firstIndex(where: { $0.id == reminderID }) else {
                continue
            }

            var reminder = data.reminders[index]
            let message = reminderMessage(for: reminder)
            do {
                try await telegram.sendMessage(
                    token: data.settings.botToken,
                    chatID: reminder.chatID,
                    text: message
                )
                reminder.status = .sent
                reminder.sentAt = Date()
                reminder.lastError = nil
                sent += 1
            } catch {
                reminder.status = .failed
                reminder.attempts += 1
                reminder.lastError = error.localizedDescription
                failed += 1
            }
            data.reminders[index] = reminder
        }

        persist(success: language.reminderSendComplete(sent: sent, failed: failed))
    }

    @discardableResult
    func sendManualTelegramMessage(to servantIDs: Set<UUID>, message: String) async -> Bool {
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else {
            errorMessage = localized("Enter a message to send.")
            return false
        }

        guard !servantIDs.isEmpty else {
            errorMessage = localized("Select at least one servant.")
            return false
        }

        let recipients = data.servants
            .filter { servantIDs.contains($0.id) }
            .compactMap { servant -> (servant: Servant, chatID: String)? in
                guard let chatID = servant.telegramChatID?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !chatID.isEmpty else {
                    return nil
                }
                return (servant, chatID)
            }
            .sorted { $0.servant.name.localizedCaseInsensitiveCompare($1.servant.name) == .orderedAscending }

        guard !recipients.isEmpty else {
            errorMessage = localized("Selected servants are not linked to Telegram yet.")
            return false
        }

        var sent = 0
        var failed = 0
        var lastError: String?

        for recipient in recipients {
            do {
                try await telegram.sendMessage(
                    token: data.settings.botToken,
                    chatID: recipient.chatID,
                    text: trimmedMessage
                )
                sent += 1
            } catch {
                failed += 1
                lastError = error.localizedDescription
            }
        }

        if sent == 0 {
            errorMessage = localized(lastError ?? "Telegram could not send the message.")
            return false
        }

        noticeMessage = language.manualMessageComplete(sent: sent, failed: failed)
        return sent > 0
    }

    private func assignmentHistory(before date: Date) -> (byTask: [String: Int], byServant: [UUID: Int]) {
        var byTask: [String: Int] = [:]
        var byServant: [UUID: Int] = [:]

        for schedule in data.schedules where schedule.startsAt < date {
            for assignment in schedule.assignments {
                guard let servantID = assignment.servantID else { continue }
                byServant[servantID, default: 0] += 1
                byTask["\(servantID.uuidString)-\(assignment.taskID.uuidString)", default: 0] += 1
            }
        }
        return (byTask, byServant)
    }

    private func bestServant(
        for task: TaskTemplate,
        alreadyAssigned: Set<UUID>,
        history: (byTask: [String: Int], byServant: [UUID: Int])
    ) -> Servant? {
        data.servants
            .filter { servant in
                !alreadyAssigned.contains(servant.id) && isServant(servant, qualifiedFor: task.qualifiedRoles)
            }
            .sorted { left, right in
                let leftTaskCount = history.byTask["\(left.id.uuidString)-\(task.id.uuidString)", default: 0]
                let rightTaskCount = history.byTask["\(right.id.uuidString)-\(task.id.uuidString)", default: 0]
                if leftTaskCount != rightTaskCount { return leftTaskCount < rightTaskCount }

                let leftTotal = history.byServant[left.id, default: 0]
                let rightTotal = history.byServant[right.id, default: 0]
                if leftTotal != rightTotal { return leftTotal < rightTotal }

                return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
            }
            .first
    }

    private func isServant(_ servant: Servant, qualifiedFor roles: [ServantRole]) -> Bool {
        roles.isEmpty || !Set(servant.roles).isDisjoint(with: Set(roles))
    }

    private func rebuildReminders(forScheduleAt scheduleIndex: Int) {
        let schedule = data.schedules[scheduleIndex]
        data.reminders.removeAll { $0.scheduleID == schedule.id }

        let reminderTimes = schedule.kind == .recurringSunday
            ? standardWeeklyReminderTimes(for: schedule.startsAt)
            : customReminderTimes(createdAt: schedule.createdAt, eventDate: schedule.startsAt)

        for assignment in schedule.assignments {
            guard let servantID = assignment.servantID,
                  let servant = servant(id: servantID),
                  let chatID = servant.telegramChatID,
                  !chatID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }

            for time in reminderTimes {
                data.reminders.append(
                    Reminder(
                        scheduleID: schedule.id,
                        assignmentID: assignment.id,
                        servantID: servantID,
                        chatID: chatID,
                        taskName: assignment.taskName,
                        eventTitle: schedule.title,
                        eventDate: schedule.startsAt,
                        scheduledAt: time
                    )
                )
            }
        }
        data.reminders.sort { $0.scheduledAt < $1.scheduledAt }
    }

    private func standardWeeklyReminderTimes(for serviceDate: Date) -> [Date] {
        var calendar = Calendar.current
        calendar.timeZone = .current
        let serviceDay = calendar.startOfDay(for: serviceDate)
        let friday = calendar.date(byAdding: .day, value: -2, to: serviceDay) ?? serviceDay
        let saturday = calendar.date(byAdding: .day, value: -1, to: serviceDay) ?? serviceDay
        return [
            calendar.date(bySettingHour: 18, minute: 0, second: 0, of: friday),
            calendar.date(bySettingHour: 18, minute: 0, second: 0, of: saturday),
            calendar.date(bySettingHour: 7, minute: 0, second: 0, of: serviceDay)
        ].compactMap { $0 }
    }

    private func customReminderTimes(createdAt: Date, eventDate: Date) -> [Date] {
        let interval = eventDate.timeIntervalSince(createdAt)
        guard interval > 0 else { return [] }

        let first = createdAt.addingTimeInterval(interval / 3)
        let second = createdAt.addingTimeInterval(interval * 2 / 3)
        let finalLead = min(3600, max(300, interval / 10))
        let third = eventDate.addingTimeInterval(-finalLead)
        return [first, second, third]
            .filter { $0 > Date() && $0 < eventDate }
            .sorted()
    }

    private func reminderMessage(for reminder: Reminder) -> String {
        language.reminderMessage(
            taskName: reminder.taskName,
            eventDate: reminder.eventDate,
            churchName: data.settings.churchName
        )
    }

    private func migrateTaskCatalogIfNeeded() {
        guard data.taskCatalogRevision < AppData.currentTaskCatalogRevision else {
            return
        }

        let existingKeys = Set(data.tasks.map { "\($0.kind.rawValue)|\($0.name.lowercased())" })
        let missingTasks = AppData.defaultTasks.filter {
            !existingKeys.contains("\($0.kind.rawValue)|\($0.name.lowercased())")
        }

        data.tasks.append(contentsOf: missingTasks)
        data.taskCatalogRevision = AppData.currentTaskCatalogRevision
        persist(success: missingTasks.isEmpty ? nil : localized("Task catalog updated."))
    }

    private func persist(success: String? = nil) {
        do {
            try storage.save(data)
            if let success {
                noticeMessage = success
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
