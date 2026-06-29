import Foundation

enum AppLanguage: String, Codable, CaseIterable, Identifiable, Hashable {
    case english = "en"
    case amharic = "am"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english:
            return "English"
        case .amharic:
            return "አማርኛ"
        }
    }

    var locale: Locale {
        switch self {
        case .english:
            return Locale(identifier: "en_US")
        case .amharic:
            return Locale(identifier: "am_ET")
        }
    }

    func text(_ key: String) -> String {
        guard self != .english,
              let path = Bundle.main.path(forResource: rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return key
        }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }
}
extension AppLanguage {
    func assignmentCount(assigned: Int, total: Int) -> String {
        switch self {
        case .english:
            return "\(assigned)/\(total) assigned"
        case .amharic:
            return "\(assigned)/\(total) ተመድቧል"
        }
    }

    func linkedToTelegram(_ count: Int) -> String {
        switch self {
        case .english:
            return "\(count) linked to Telegram"
        case .amharic:
            return "\(count) ከቴሌግራም ጋር ተገናኝቷል"
        }
    }

    func peopleRequired(_ count: Int) -> String {
        switch self {
        case .english:
            return "\(count) people"
        case .amharic:
            return "\(count) ሰዎች"
        }
    }

    func linkedServants(_ count: Int) -> String {
        switch self {
        case .english:
            return count == 1 ? "Linked 1 servant from Telegram." : "Linked \(count) servants from Telegram."
        case .amharic:
            return count == 1 ? "1 አገልጋይ ከቴሌግራም ተገናኝቷል።" : "\(count) አገልጋዮች ከቴሌግራም ተገናኝተዋል።"
        }
    }

    func weeklyScheduleGenerated(for date: Date) -> String {
        switch self {
        case .english:
            return "Weekly schedule generated for \(date.localizedDayAndTime(language: self))."
        case .amharic:
            return "ሳምናዊ መርሐግብር ለ\(date.localizedDayAndTime(language: self)) ተዘጋጅቷል።"
        }
    }

    func reminderSendComplete(sent: Int, failed: Int) -> String {
        switch self {
        case .english:
            return "Reminder send complete. Sent: \(sent), Failed: \(failed)."
        case .amharic:
            return "ማስታወሻ መላክ ተጠናቋል። የተላከ፦ \(sent), ያልተሳካ፦ \(failed)።"
        }
    }

    func manualMessageComplete(sent: Int, failed: Int) -> String {
        switch self {
        case .english:
            return "Manual Telegram message complete. Sent: \(sent), Failed: \(failed)."
        case .amharic:
            return "የእጅ ቴሌግራም መልእክት ተጠናቋል። የተላከ፦ \(sent), ያልተሳካ፦ \(failed)።"
        }
    }

    func selectedRecipients(_ count: Int) -> String {
        switch self {
        case .english:
            return count == 1 ? "1 selected" : "\(count) selected"
        case .amharic:
            return count == 1 ? "1 ተመርጧል" : "\(count) ተመርጠዋል"
        }
    }

    func reminderMessage(taskName: String, eventDate: Date, churchName: String) -> String {
        let localizedTaskName = text(taskName)
        let trimmedChurchName = churchName.trimmingCharacters(in: .whitespacesAndNewlines)
        switch self {
        case .english:
            let from = trimmedChurchName.isEmpty ? "" : "from \(trimmedChurchName) "
            return "Reminder \(from)about your assignment for \(localizedTaskName) on \(eventDate.localizedShortDateAndTime(language: self))."
        case .amharic:
            let from = trimmedChurchName.isEmpty ? "" : "ከ\(trimmedChurchName) "
            return "\(from)ማስታወሻ፦ ለ\(localizedTaskName) በ\(eventDate.localizedShortDateAndTime(language: self)) የተመደቡትን አገልግሎት ያስታውሳል።"
        }
    }
}

extension ServantRole {
    func localizedName(_ language: AppLanguage) -> String {
        language.text(rawValue)
    }
}

extension ScheduleKind {
    func localizedName(_ language: AppLanguage) -> String {
        switch self {
        case .recurringSunday:
            return language.text("Recurring Weekly Service")
        case .customOccasion:
            return language.text(rawValue)
        }
    }
}

extension ReminderStatus {
    func localizedName(_ language: AppLanguage) -> String {
        language.text(rawValue)
    }
}

extension Date {
    func localizedShortDateAndTime(language: AppLanguage) -> String {
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }

    func localizedDayAndTime(language: AppLanguage) -> String {
        guard language != .english else {
            return dayAndTime
        }

        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.setLocalizedDateFormatFromTemplate("EEE MMM d h:mm a")
        return formatter.string(from: self)
    }
}
