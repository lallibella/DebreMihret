import Foundation

enum ServantRole: String, Codable, CaseIterable, Identifiable, Hashable {
    case priest = "Priest"
    case deacon = "Deacon"
    case sundaySchoolTeacher = "Sunday School Teacher"
    case cleaner = "Cleaner"
    case foodService = "Food Service"
    case security = "Security / Surrounding Eye"

    var id: String { rawValue }
}

enum ScheduleKind: String, Codable, CaseIterable, Identifiable {
    case recurringSunday = "Recurring Sunday Service"  // rawValue kept for JSON compat
    case customOccasion = "Custom Festival Occasion"

    var id: String { rawValue }
}

enum ReminderStatus: String, Codable, CaseIterable {
    case pending = "Pending"
    case sent = "Sent"
    case failed = "Failed"
    case skipped = "Skipped"
}

struct Servant: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var phoneNumber: String
    var telegramChatID: String?
    var roles: [ServantRole]
    var notes: String

    init(
        id: UUID = UUID(),
        name: String,
        phoneNumber: String,
        telegramChatID: String? = nil,
        roles: [ServantRole] = [],
        notes: String = ""
    ) {
        self.id = id
        self.name = name
        self.phoneNumber = phoneNumber
        self.telegramChatID = telegramChatID
        self.roles = roles
        self.notes = notes
    }

    var isTelegramLinked: Bool {
        guard let telegramChatID else { return false }
        return !telegramChatID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct TaskTemplate: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var requiredPeople: Int
    var kind: ScheduleKind
    var qualifiedRoles: [ServantRole]

    init(
        id: UUID = UUID(),
        name: String,
        requiredPeople: Int,
        kind: ScheduleKind,
        qualifiedRoles: [ServantRole] = []
    ) {
        self.id = id
        self.name = name
        self.requiredPeople = max(1, requiredPeople)
        self.kind = kind
        self.qualifiedRoles = qualifiedRoles
    }
}

struct Assignment: Identifiable, Codable, Hashable {
    var id: UUID
    var taskID: UUID
    var taskName: String
    var qualifiedRoles: [ServantRole]
    var servantID: UUID?
    var servantName: String?

    init(
        id: UUID = UUID(),
        taskID: UUID,
        taskName: String,
        qualifiedRoles: [ServantRole],
        servantID: UUID? = nil,
        servantName: String? = nil
    ) {
        self.id = id
        self.taskID = taskID
        self.taskName = taskName
        self.qualifiedRoles = qualifiedRoles
        self.servantID = servantID
        self.servantName = servantName
    }
}

struct Schedule: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var startsAt: Date
    var kind: ScheduleKind
    var createdAt: Date
    var finalizedAt: Date?
    var assignments: [Assignment]

    init(
        id: UUID = UUID(),
        title: String,
        startsAt: Date,
        kind: ScheduleKind,
        createdAt: Date = Date(),
        finalizedAt: Date? = nil,
        assignments: [Assignment] = []
    ) {
        self.id = id
        self.title = title
        self.startsAt = startsAt
        self.kind = kind
        self.createdAt = createdAt
        self.finalizedAt = finalizedAt
        self.assignments = assignments
    }

    var isFinalized: Bool {
        finalizedAt != nil
    }
}

struct Reminder: Identifiable, Codable, Hashable {
    var id: UUID
    var scheduleID: UUID
    var assignmentID: UUID
    var servantID: UUID
    var chatID: String
    var taskName: String
    var eventTitle: String
    var eventDate: Date
    var scheduledAt: Date
    var sentAt: Date?
    var attempts: Int
    var status: ReminderStatus
    var lastError: String?

    init(
        id: UUID = UUID(),
        scheduleID: UUID,
        assignmentID: UUID,
        servantID: UUID,
        chatID: String,
        taskName: String,
        eventTitle: String,
        eventDate: Date,
        scheduledAt: Date,
        sentAt: Date? = nil,
        attempts: Int = 0,
        status: ReminderStatus = .pending,
        lastError: String? = nil
    ) {
        self.id = id
        self.scheduleID = scheduleID
        self.assignmentID = assignmentID
        self.servantID = servantID
        self.chatID = chatID
        self.taskName = taskName
        self.eventTitle = eventTitle
        self.eventDate = eventDate
        self.scheduledAt = scheduledAt
        self.sentAt = sentAt
        self.attempts = attempts
        self.status = status
        self.lastError = lastError
    }
}

struct AppSettings: Codable, Hashable {
    var churchName: String
    var botUsername: String
    var botToken: String
    var telegramUpdateOffset: Int
    var language: AppLanguage
    var appLockEnabled: Bool
    var securitySetupCompleted: Bool
    var pinSalt: String?
    var pinHash: String?
    /// Weekday numbers for recurring weekly services (1 = Sunday … 7 = Saturday, matching Calendar.weekday).
    var recurringServiceDays: [Int]

    init(
        churchName: String = "",
        botUsername: String = "",
        botToken: String = "",
        telegramUpdateOffset: Int = 0,
        language: AppLanguage = .english,
        appLockEnabled: Bool = false,
        securitySetupCompleted: Bool = false,
        pinSalt: String? = nil,
        pinHash: String? = nil,
        recurringServiceDays: [Int] = [1]
    ) {
        self.churchName = churchName
        self.botUsername = botUsername
        self.botToken = botToken
        self.telegramUpdateOffset = telegramUpdateOffset
        self.language = language
        self.appLockEnabled = appLockEnabled
        self.securitySetupCompleted = securitySetupCompleted
        self.pinSalt = pinSalt
        self.pinHash = pinHash
        self.recurringServiceDays = recurringServiceDays.isEmpty ? [1] : recurringServiceDays
    }

    var appDisplayName: String {
        let name = churchName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Debre Mihret St Michael Church" : name
    }
}

extension AppSettings {
    enum CodingKeys: String, CodingKey {
        case churchName
        case botUsername
        case botToken
        case telegramUpdateOffset
        case language
        case appLockEnabled
        case securitySetupCompleted
        case pinSalt
        case pinHash
        case recurringServiceDays
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        churchName = try container.decodeIfPresent(String.self, forKey: .churchName) ?? ""
        botUsername = try container.decodeIfPresent(String.self, forKey: .botUsername) ?? ""
        botToken = try container.decodeIfPresent(String.self, forKey: .botToken) ?? ""
        telegramUpdateOffset = try container.decodeIfPresent(Int.self, forKey: .telegramUpdateOffset) ?? 0
        language = try container.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .english
        appLockEnabled = try container.decodeIfPresent(Bool.self, forKey: .appLockEnabled) ?? false
        pinSalt = try container.decodeIfPresent(String.self, forKey: .pinSalt)
        pinHash = try container.decodeIfPresent(String.self, forKey: .pinHash)
        securitySetupCompleted = try container.decodeIfPresent(Bool.self, forKey: .securitySetupCompleted) ?? appLockEnabled
        let days = try container.decodeIfPresent([Int].self, forKey: .recurringServiceDays) ?? [1]
        recurringServiceDays = days.isEmpty ? [1] : days
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(churchName, forKey: .churchName)
        try container.encode(botUsername, forKey: .botUsername)
        try container.encode(botToken, forKey: .botToken)
        try container.encode(telegramUpdateOffset, forKey: .telegramUpdateOffset)
        try container.encode(language, forKey: .language)
        try container.encode(appLockEnabled, forKey: .appLockEnabled)
        try container.encode(securitySetupCompleted, forKey: .securitySetupCompleted)
        try container.encodeIfPresent(pinSalt, forKey: .pinSalt)
        try container.encodeIfPresent(pinHash, forKey: .pinHash)
        try container.encode(recurringServiceDays, forKey: .recurringServiceDays)
    }
}

struct AppData: Codable, Hashable {
    var servants: [Servant]
    var tasks: [TaskTemplate]
    var schedules: [Schedule]
    var reminders: [Reminder]
    var settings: AppSettings
    var taskCatalogRevision: Int

    static let currentTaskCatalogRevision = 1

    static var defaultTasks: [TaskTemplate] {
        [
            TaskTemplate(name: "Priest", requiredPeople: 1, kind: .recurringSunday, qualifiedRoles: [.priest]),
            TaskTemplate(name: "Deacon", requiredPeople: 2, kind: .recurringSunday, qualifiedRoles: [.deacon]),
            TaskTemplate(name: "Sunday School", requiredPeople: 1, kind: .recurringSunday, qualifiedRoles: [.sundaySchoolTeacher]),
            TaskTemplate(name: "Cleaning", requiredPeople: 2, kind: .recurringSunday, qualifiedRoles: [.cleaner]),
            TaskTemplate(name: "Food Service", requiredPeople: 2, kind: .recurringSunday, qualifiedRoles: [.foodService]),
            TaskTemplate(name: "Samosa Maker", requiredPeople: 1, kind: .recurringSunday, qualifiedRoles: [.foodService]),
            TaskTemplate(name: "Security / Surrounding Eye", requiredPeople: 1, kind: .recurringSunday, qualifiedRoles: [.security]),
            TaskTemplate(name: "Parking Coordinator", requiredPeople: 1, kind: .recurringSunday, qualifiedRoles: [.security]),
            TaskTemplate(name: "Festival Food Service", requiredPeople: 3, kind: .customOccasion, qualifiedRoles: [.foodService]),
            TaskTemplate(name: "Festival Security", requiredPeople: 2, kind: .customOccasion, qualifiedRoles: [.security]),
            TaskTemplate(name: "Festival Deacon Service", requiredPeople: 2, kind: .customOccasion, qualifiedRoles: [.deacon])
        ]
    }

    static var seed: AppData {
        AppData(
            servants: [],
            tasks: defaultTasks,
            schedules: [],
            reminders: [],
            settings: AppSettings(),
            taskCatalogRevision: currentTaskCatalogRevision
        )
    }
}

extension AppData {
    enum CodingKeys: String, CodingKey {
        case servants
        case tasks
        case schedules
        case reminders
        case settings
        case taskCatalogRevision
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        servants = try container.decode([Servant].self, forKey: .servants)
        tasks = try container.decode([TaskTemplate].self, forKey: .tasks)
        schedules = try container.decode([Schedule].self, forKey: .schedules)
        reminders = try container.decode([Reminder].self, forKey: .reminders)
        settings = try container.decode(AppSettings.self, forKey: .settings)
        taskCatalogRevision = try container.decodeIfPresent(Int.self, forKey: .taskCatalogRevision) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(servants, forKey: .servants)
        try container.encode(tasks, forKey: .tasks)
        try container.encode(schedules, forKey: .schedules)
        try container.encode(reminders, forKey: .reminders)
        try container.encode(settings, forKey: .settings)
        try container.encode(taskCatalogRevision, forKey: .taskCatalogRevision)
    }
}

extension Date {
    /// Returns the next service date for the given weekday numbers (1 = Sunday … 7 = Saturday).
    /// Picks the nearest upcoming day; if today is a service day but the 9 AM service has passed, advances a full week.
    static func nextRecurringServiceDate(days: [Int], from now: Date = Date()) -> Date {
        var calendar = Calendar.current
        calendar.timeZone = .current
        let startOfToday = calendar.startOfDay(for: now)
        let todayWeekday = calendar.component(.weekday, from: startOfToday)
        let serviceTimeToday = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: startOfToday)!
        let activeDays = days.isEmpty ? [1] : days

        var bestOffset = 7
        for day in activeDays {
            var offset = (day - todayWeekday + 7) % 7
            if offset == 0 && now >= serviceTimeToday { offset = 7 }
            if offset < bestOffset { bestOffset = offset }
        }

        let targetDay = calendar.date(byAdding: .day, value: bestOffset, to: startOfToday) ?? startOfToday
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: targetDay) ?? targetDay
    }

    var shortDateAndTime: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }

    var dayAndTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d 'at' h:mm a"
        return formatter.string(from: self)
    }
}

extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}
