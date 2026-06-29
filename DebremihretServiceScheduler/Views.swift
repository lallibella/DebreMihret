import LocalAuthentication
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct LockGateView: View {
    @EnvironmentObject private var store: SchedulerStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var unlocked = false
    @State private var pin = ""
    @State private var isAuthenticating = false

    var body: some View {
        Group {
            if !store.data.settings.securitySetupCompleted {
                SecuritySetupView {
                    unlocked = true
                }
            } else if store.data.settings.appLockEnabled && !unlocked {
                lockScreen
                    .onAppear {
                        unlockWithDeviceAuthentication(showError: false)
                    }
            } else {
                MainTabs()
            }
        }
        .environment(\.locale, store.language.locale)
        .onChange(of: scenePhase) { newPhase in
            switch newPhase {
            case .background:
                if store.data.settings.appLockEnabled {
                    unlocked = false
                    pin = ""
                }
            case .active:
                if store.data.settings.securitySetupCompleted,
                   store.data.settings.appLockEnabled,
                   !unlocked {
                    unlockWithDeviceAuthentication(showError: false)
                }
            default:
                break
            }
        }
        .alertMessages(store: store)
    }

    private var lockScreen: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "lock.shield")
                .font(.system(size: 54, weight: .semibold))
                .foregroundStyle(.teal)

            VStack(spacing: 8) {
                FittedHeaderTitle(text: store.localized(store.data.settings.appDisplayName))
                Text("Unlock to manage servants, schedules, and reminders.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                unlockWithDeviceAuthentication(showError: true)
            } label: {
                Label("Unlock with Face ID or Passcode", systemImage: "faceid")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isAuthenticating)

            if store.data.settings.pinHash != nil {
                SecureField("4-digit PIN", text: $pin)
                    .textContentType(.oneTimeCode)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: pin) { newValue in
                        pin = String(newValue.filter(\.isNumber).prefix(4))
                    }

                Button("Unlock with PIN") {
                    if store.verifyPIN(pin) {
                        unlocked = true
                        pin = ""
                    } else {
                        store.errorMessage = store.localized("Incorrect PIN.")
                    }
                }
                .buttonStyle(.bordered)
            }
            Spacer()
        }
        .padding(28)
    }

    private func unlockWithDeviceAuthentication(showError: Bool) {
        guard !isAuthenticating else { return }

        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            if showError {
                store.errorMessage = error?.localizedDescription ?? store.localized("Device authentication is not available on this phone.")
            }
            return
        }

        isAuthenticating = true
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Authenticate to access \(store.data.settings.appDisplayName) admin data") { success, authenticationError in
            DispatchQueue.main.async {
                isAuthenticating = false
                if success {
                    unlocked = true
                } else {
                    let nsError = authenticationError as NSError?
                    let wasUserCancel = nsError?.domain == LAError.errorDomain && (
                        nsError?.code == LAError.userCancel.rawValue ||
                        nsError?.code == LAError.systemCancel.rawValue ||
                        nsError?.code == LAError.appCancel.rawValue
                    )
                    if showError || !wasUserCancel {
                        store.errorMessage = authenticationError?.localizedDescription ?? store.localized("Unable to unlock.")
                    }
                }
            }
        }
    }
}

struct SecuritySetupView: View {
    @EnvironmentObject private var store: SchedulerStore
    @State private var pin = ""
    @State private var confirmPIN = ""
    var onComplete: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "person.badge.key")
                .font(.system(size: 54, weight: .semibold))
                .foregroundStyle(.teal)

            VStack(spacing: 8) {
                FittedHeaderTitle(text: store.localized("Protect Admin Access"))
                Text("Create a 4-digit PIN. Face ID, Touch ID, or the device passcode will be used when available.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Picker("App Language", selection: Binding(
                get: { store.data.settings.language },
                set: { newValue in store.updateSettings { $0.language = newValue } }
            )) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.displayName).tag(language)
                }
            }
            .pickerStyle(.segmented)

            VStack(spacing: 12) {
                SecureField("4-digit PIN", text: $pin)
                    .textContentType(.oneTimeCode)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: pin) { newValue in
                        pin = String(newValue.filter(\.isNumber).prefix(4))
                    }

                SecureField("Confirm PIN", text: $confirmPIN)
                    .textContentType(.oneTimeCode)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: confirmPIN) { newValue in
                        confirmPIN = String(newValue.filter(\.isNumber).prefix(4))
                    }
            }

            Button {
                guard pin == confirmPIN else {
                    store.errorMessage = store.localized("The PIN entries do not match.")
                    return
                }
                if store.setPIN(pin) {
                    onComplete()
                }
            } label: {
                Label("Enable App Lock", systemImage: "lock.shield")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(pin.count != 4 || confirmPIN.count != 4)

            Spacer()
        }
        .padding(28)
    }
}

struct MainTabs: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "rectangle.grid.2x2") }

            ServantsView()
                .tabItem { Label("Servants", systemImage: "person.3") }

            TasksView()
                .tabItem { Label("Tasks", systemImage: "checklist") }

            SchedulesView()
                .tabItem { Label("Schedules", systemImage: "calendar") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(.teal)
    }
}

private struct FittedHeaderTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.title2.bold())
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.65)
            .allowsTightening(true)
            .frame(maxWidth: .infinity)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct FittedNavigationTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.headline)
            .fontWeight(.semibold)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .allowsTightening(true)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }
}

struct DashboardView: View {
    @EnvironmentObject private var store: SchedulerStore
    @State private var showManualTelegramMessage = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    DashboardMetric(title: store.localized("Servants"), value: "\(store.data.servants.count)", detail: store.language.linkedToTelegram(store.linkedServantCount), icon: "person.3.fill")
                    DashboardMetric(title: store.localized("Tasks"), value: "\(store.data.tasks.count)", detail: store.localized("Recurring and custom"), icon: "checklist.checked")
                    DashboardMetric(title: store.localized("Pending Reminders"), value: "\(store.pendingReminderCount)", detail: store.nextPendingReminder?.scheduledAt.localizedDayAndTime(language: store.language) ?? store.localized("None scheduled"), icon: "bell.badge")
                }

                Section("Actions") {
                    Button {
                        store.generateWeeklySchedule()
                    } label: {
                        Label("Generate Weekly Schedule", systemImage: "wand.and.stars")
                    }

                    Button {
                        Task { await store.syncTelegramLinks() }
                    } label: {
                        Label("Sync Telegram Links", systemImage: "link")
                    }

                    Button {
                        Task { await store.sendDueReminders() }
                    } label: {
                        Label("Send Due Reminders", systemImage: "paperplane")
                    }

                    Button {
                        showManualTelegramMessage = true
                    } label: {
                        Label("Manual Telegram Message", systemImage: "paperplane.circle")
                    }
                }

                Section("Upcoming") {
                    let upcoming = store.data.schedules
                        .filter { $0.startsAt >= Calendar.current.startOfDay(for: Date()) }
                        .prefix(5)

                    if upcoming.isEmpty {
                        Text("No upcoming schedules yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(upcoming)) { schedule in
                            NavigationLink {
                                ScheduleDetailView(scheduleID: schedule.id)
                            } label: {
                                ScheduleRow(schedule: schedule)
                            }
                        }
                    }
                }
            }
            .navigationTitle(store.localized(store.data.settings.appDisplayName))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    FittedNavigationTitle(text: store.localized(store.data.settings.appDisplayName))
                }
            }
            .sheet(isPresented: $showManualTelegramMessage) {
                ManualTelegramMessageView()
            }
        }
    }
}

struct ManualTelegramMessageView: View {
    @EnvironmentObject private var store: SchedulerStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedServantIDs: Set<UUID> = []
    @State private var message = ""
    @State private var isSending = false

    private var linkedServants: [Servant] {
        store.data.servants
            .filter(\.isTelegramLinked)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var unlinkedServants: [Servant] {
        store.data.servants
            .filter { !$0.isTelegramLinked }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var canSend: Bool {
        !isSending &&
        !selectedServantIDs.isEmpty &&
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Message") {
                    TextEditor(text: $message)
                        .frame(minHeight: 120)

                    Text("Messages are sent by the \(store.data.settings.appDisplayName) Telegram bot.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button {
                        selectedServantIDs = Set(linkedServants.map(\.id))
                    } label: {
                        Label("Select All Linked Servants", systemImage: "checkmark.circle")
                    }
                    .disabled(linkedServants.isEmpty)

                    Button {
                        selectedServantIDs.removeAll()
                    } label: {
                        Label("Clear Selection", systemImage: "xmark.circle")
                    }
                    .disabled(selectedServantIDs.isEmpty)
                } footer: {
                    Text(store.language.selectedRecipients(selectedServantIDs.count))
                }

                Section("Recipients") {
                    if linkedServants.isEmpty {
                        Text("No servants are linked to Telegram yet.")
                            .foregroundStyle(.secondary)
                    }

                    ForEach(linkedServants) { servant in
                        Toggle(isOn: Binding(
                            get: { selectedServantIDs.contains(servant.id) },
                            set: { isSelected in
                                if isSelected {
                                    selectedServantIDs.insert(servant.id)
                                } else {
                                    selectedServantIDs.remove(servant.id)
                                }
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(servant.name)
                                Text(servant.roles.map { $0.localizedName(store.language) }.joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }

                if !unlinkedServants.isEmpty {
                    Section("Not Linked") {
                        ForEach(unlinkedServants) { servant in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(servant.name)
                                    Text(servant.roles.map { $0.localizedName(store.language) }.joined(separator: ", "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                Spacer()
                                Text("Not linked")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Manual Message")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            isSending = true
                            let sent = await store.sendManualTelegramMessage(to: selectedServantIDs, message: message)
                            isSending = false
                            if sent {
                                dismiss()
                            }
                        }
                    } label: {
                        if isSending {
                            ProgressView()
                        } else {
                            Text("Send")
                        }
                    }
                    .disabled(!canSend)
                }
            }
        }
    }
}

struct DashboardMetric: View {
    var title: String
    var value: String
    var detail: String
    var icon: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .frame(width: 36, height: 36)
                .background(.teal.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(.teal)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(value)
                .font(.title3.bold())
        }
    }
}

struct ServantsView: View {
    @EnvironmentObject private var store: SchedulerStore
    @State private var editorServant: Servant?

    var body: some View {
        NavigationStack {
            List {
                if store.data.servants.isEmpty {
                    Text("Add servants to start generating schedules.")
                        .foregroundStyle(.secondary)
                }

                ForEach(store.data.servants.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) { servant in
                    NavigationLink {
                        ServantDetailView(servantID: servant.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(servant.name)
                                    .font(.headline)
                                Spacer()
                                Image(systemName: servant.isTelegramLinked ? "paperplane.fill" : "paperplane")
                                    .foregroundStyle(servant.isTelegramLinked ? .teal : .secondary)
                            }
                            Text(servant.roles.map { $0.localizedName(store.language) }.joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            store.deleteServant(id: servant.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("Servants")
            .toolbar {
                Button {
                    editorServant = Servant(name: "", phoneNumber: "")
                } label: {
                    Label("Add Servant", systemImage: "plus")
                }
            }
            .sheet(item: $editorServant) { servant in
                ServantEditorView(servant: servant)
            }
        }
    }
}

struct ServantDetailView: View {
    @EnvironmentObject private var store: SchedulerStore
    @Environment(\.dismiss) private var dismiss
    @State private var editorServant: Servant?
    var servantID: UUID

    var body: some View {
        Group {
            if let servant = store.servant(id: servantID) {
                Form {
                    Section {
                        LabeledContent("Phone", value: servant.phoneNumber.isEmpty ? store.localized("Not set") : servant.phoneNumber)
                        LabeledContent("Telegram", value: servant.isTelegramLinked ? store.localized("Linked") : store.localized("Not linked"))
                        if let chatID = servant.telegramChatID, !chatID.isEmpty {
                            LabeledContent("Chat ID", value: chatID)
                        }
                    }

                    Section("Roles") {
                        ForEach(servant.roles, id: \.self) { role in
                            Label(role.localizedName(store.language), systemImage: "checkmark.circle")
                        }
                    }

                    Section("Telegram Link") {
                        if let url = store.linkURL(for: servant) {
                            ShareLink(item: url) {
                                Label("Share Link", systemImage: "square.and.arrow.up")
                            }
                            Button {
                                UIPasteboard.general.url = url
                                store.noticeMessage = store.localized("Telegram link copied.")
                            } label: {
                                Label("Copy Link", systemImage: "doc.on.doc")
                            }
                            Link(destination: url) {
                                Label("Open in Telegram", systemImage: "paperplane")
                            }
                        } else {
                            Text("Set the bot username in Settings first.")
                                .foregroundStyle(.secondary)
                        }
                    }

                    if !servant.notes.isEmpty {
                        Section("Notes") {
                            Text(servant.notes)
                        }
                    }

                    Section {
                        Button("Delete Servant", role: .destructive) {
                            store.deleteServant(id: servant.id)
                            dismiss()
                        }
                    }
                }
                .navigationTitle(servant.name)
                .toolbar {
                    Button("Edit") {
                        editorServant = servant
                    }
                }
                .sheet(item: $editorServant) { servant in
                    ServantEditorView(servant: servant)
                }
            } else {
                ContentUnavailableView("Servant Not Found", systemImage: "person.crop.circle.badge.questionmark")
            }
        }
    }
}

struct ServantEditorView: View {
    @EnvironmentObject private var store: SchedulerStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Servant

    init(servant: Servant) {
        _draft = State(initialValue: servant)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile") {
                    TextField("Name", text: $draft.name)
                    TextField("Phone Number", text: $draft.phoneNumber)
                        .keyboardType(.phonePad)
                    TextField("Telegram Chat ID", text: Binding(
                        get: { draft.telegramChatID ?? "" },
                        set: { draft.telegramChatID = $0.isEmpty ? nil : $0 }
                    ))
                    .keyboardType(.numberPad)
                }

                Section("Roles") {
                    RoleChecklist(selection: $draft.roles)
                }

                Section("Notes") {
                    TextField("Optional notes", text: $draft.notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle(draft.name.isEmpty ? "New Servant" : "Edit Servant")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !name.isEmpty else {
                            store.errorMessage = store.localized("Enter a servant name.")
                            return
                        }
                        draft.name = name
                        draft.roles = draft.roles.uniqued()
                        store.upsertServant(draft)
                        dismiss()
                    }
                }
            }
        }
    }
}

struct TasksView: View {
    @EnvironmentObject private var store: SchedulerStore
    @State private var editorTask: TaskTemplate?

    var body: some View {
        NavigationStack {
            List {
                ForEach(ScheduleKind.allCases) { kind in
                    let tasks = store.data.tasks
                        .filter { $0.kind == kind }
                        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                    Section(kind.localizedName(store.language)) {
                        if tasks.isEmpty {
                            Text("No tasks in this group.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(tasks) { task in
                            Button {
                                editorTask = task
                            } label: {
                                TaskRow(task: task)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Tasks")
            .toolbar {
                Button {
                    editorTask = TaskTemplate(name: "", requiredPeople: 1, kind: .recurringSunday)
                } label: {
                    Label("Add Task", systemImage: "plus")
                }
            }
            .sheet(item: $editorTask) { task in
                TaskEditorView(task: task)
            }
        }
    }
}

struct TaskRow: View {
    @EnvironmentObject private var store: SchedulerStore
    var task: TaskTemplate

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(store.localized(task.name))
                    .font(.headline)
                Spacer()
                Text("\(task.requiredPeople)")
                    .font(.headline)
                    .foregroundStyle(.teal)
            }
            Text(task.qualifiedRoles.isEmpty ? store.localized("Any role") : task.qualifiedRoles.map { $0.localizedName(store.language) }.joined(separator: ", "))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct TaskEditorView: View {
    @EnvironmentObject private var store: SchedulerStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: TaskTemplate

    init(task: TaskTemplate) {
        _draft = State(initialValue: task)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    TextField("Task Name", text: $draft.name)
                    Stepper(value: $draft.requiredPeople, in: 1...20) {
                        Text("\(store.localized("People Required")): \(draft.requiredPeople)")
                    }
                    Picker("Type", selection: $draft.kind) {
                        ForEach(ScheduleKind.allCases) { kind in
                            Text(kind.localizedName(store.language)).tag(kind)
                        }
                    }
                }

                Section("Qualified Roles") {
                    RoleChecklist(selection: $draft.qualifiedRoles)
                }

                Section {
                    Button("Delete Task", role: .destructive) {
                        if let index = store.data.tasks.firstIndex(where: { $0.id == draft.id }) {
                            store.deleteTasks(at: IndexSet(integer: index))
                        }
                        dismiss()
                    }
                }
            }
            .navigationTitle(draft.name.isEmpty ? "New Task" : "Edit Task")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !name.isEmpty else {
                            store.errorMessage = store.localized("Enter a task name.")
                            return
                        }
                        draft.name = name
                        store.upsertTask(draft)
                        dismiss()
                    }
                }
            }
        }
    }
}

struct SchedulesView: View {
    @EnvironmentObject private var store: SchedulerStore
    @State private var showCustomSchedule = false

    var body: some View {
        NavigationStack {
            List {
                if store.data.schedules.isEmpty {
                    Text("Generate a weekly schedule or add a custom occasion.")
                        .foregroundStyle(.secondary)
                }

                ForEach(store.data.schedules.sorted { $0.startsAt < $1.startsAt }) { schedule in
                    NavigationLink {
                        ScheduleDetailView(scheduleID: schedule.id)
                    } label: {
                        ScheduleRow(schedule: schedule)
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            store.deleteSchedule(id: schedule.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("Schedules")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showCustomSchedule = true
                    } label: {
                        Label("Custom Occasion", systemImage: "calendar.badge.plus")
                    }
                    Button {
                        store.generateWeeklySchedule()
                    } label: {
                        Label("Generate Weekly", systemImage: "wand.and.stars")
                    }
                }
            }
            .sheet(isPresented: $showCustomSchedule) {
                NewCustomScheduleView()
            }
        }
    }
}

struct ScheduleRow: View {
    @EnvironmentObject private var store: SchedulerStore
    var schedule: Schedule

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(store.localized(schedule.title))
                    .font(.headline)
                Spacer()
                Image(systemName: schedule.isFinalized ? "checkmark.seal.fill" : "pencil.circle")
                    .foregroundStyle(schedule.isFinalized ? .teal : .secondary)
            }
            Text(schedule.startsAt.localizedDayAndTime(language: store.language))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(store.language.assignmentCount(assigned: schedule.assignments.filter { $0.servantID != nil }.count, total: schedule.assignments.count))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct ScheduleDetailView: View {
    @EnvironmentObject private var store: SchedulerStore
    var scheduleID: UUID

    var body: some View {
        Group {
            if let schedule = store.schedule(id: scheduleID) {
                Form {
                    Section {
                        LabeledContent("Date", value: schedule.startsAt.localizedShortDateAndTime(language: store.language))
                        LabeledContent("Type", value: schedule.kind.localizedName(store.language))
                        LabeledContent("Status", value: schedule.isFinalized ? store.localized("Finalized") : store.localized("Draft"))
                    }

                    Section("Assignments") {
                        ForEach(schedule.assignments) { assignment in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(store.localized(assignment.taskName))
                                    .font(.headline)
                                if !assignment.qualifiedRoles.isEmpty {
                                    Text(assignment.qualifiedRoles.map { $0.localizedName(store.language) }.joined(separator: ", "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Picker("Servant", selection: Binding<UUID?>(
                                    get: { assignment.servantID },
                                    set: { store.setAssignmentServant(scheduleID: schedule.id, assignmentID: assignment.id, servantID: $0) }
                                )) {
                                    Text("Unassigned").tag(UUID?.none)
                                    ForEach(store.eligibleServants(for: assignment)) { servant in
                                        Text(servant.name + (servant.isTelegramLinked ? "" : store.localized("  - no Telegram")))
                                            .tag(Optional(servant.id))
                                    }
                                }
                            }
                        }
                    }

                    Section("Reminder Readiness") {
                        let linkedAssignments = schedule.assignments.filter { assignment in
                            guard let servant = store.servant(id: assignment.servantID) else { return false }
                            return servant.isTelegramLinked
                        }.count
                        LabeledContent("Telegram-ready", value: "\(linkedAssignments)/\(schedule.assignments.count)")
                        LabeledContent("Prepared reminders", value: "\(store.data.reminders.filter { $0.scheduleID == schedule.id }.count)")
                    }

                    Section {
                        Button {
                            store.finalizeSchedule(id: schedule.id)
                            BackgroundReminderManager.shared.scheduleNextReminder(from: store.data.reminders)
                        } label: {
                            Label(store.localized(schedule.isFinalized ? "Refresh Reminder Plan" : "Finalize Schedule"), systemImage: "checkmark.seal")
                        }

                        Button {
                            Task { await store.sendDueReminders() }
                        } label: {
                            Label("Send Due Reminders", systemImage: "paperplane")
                        }
                    }
                }
                .navigationTitle(store.localized(schedule.title))
            } else {
                ContentUnavailableView("Schedule Not Found", systemImage: "calendar.badge.exclamationmark")
            }
        }
    }
}

struct NewCustomScheduleView: View {
    @EnvironmentObject private var store: SchedulerStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var startsAt = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var selectedTasks: Set<UUID> = []

    var body: some View {
        NavigationStack {
            Form {
                Section("Occasion") {
                    TextField("Event title", text: $title)
                    DatePicker("Date and time", selection: $startsAt, displayedComponents: [.date, .hourAndMinute])
                }

                Section("Tasks") {
                    let tasks = store.data.tasks
                        .filter { $0.kind == .customOccasion }
                        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

                    if tasks.isEmpty {
                        Text("Add custom occasion tasks in the Tasks tab first.")
                            .foregroundStyle(.secondary)
                    }

                    ForEach(tasks) { task in
                        Button {
                            if selectedTasks.contains(task.id) {
                                selectedTasks.remove(task.id)
                            } else {
                                selectedTasks.insert(task.id)
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(store.localized(task.name))
                                    Text(store.language.peopleRequired(task.requiredPeople))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: selectedTasks.contains(task.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedTasks.contains(task.id) ? .teal : .secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Custom Occasion")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        store.createCustomSchedule(title: title, startsAt: startsAt, taskIDs: selectedTasks)
                        if store.errorMessage == nil {
                            dismiss()
                        }
                    }
                }
            }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: SchedulerStore
    @State private var pin = ""
    @State private var backupPassword = ""
    @State private var exportDocument = BackupDocument(data: Data())
    @State private var isExporting = false
    @State private var isImporting = false

    private var backupFilename: String {
        let name = store.data.settings.churchName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
        return name.isEmpty ? "DebreMihretBackup.dmsbackup" : "\(name)Backup.dmsbackup"
    }

    private func weekdayName(_ weekday: Int) -> String {
        Calendar.current.weekdaySymbols[weekday - 1]
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Telegram Bot") {
                    TextField("Bot username", text: Binding(
                        get: { store.data.settings.botUsername },
                        set: { newValue in store.updateSettings { $0.botUsername = newValue } }
                    ))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                    SecureField("Bot token", text: Binding(
                        get: { store.data.settings.botToken },
                        set: { newValue in store.updateSettings { $0.botToken = newValue } }
                    ))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                    Button {
                        Task { await store.syncTelegramLinks() }
                    } label: {
                        Label("Sync Telegram Starts", systemImage: "link")
                    }
                }

                Section("Recurring Service Days") {
                    ForEach(1...7, id: \.self) { weekday in
                        Toggle(weekdayName(weekday), isOn: Binding(
                            get: { store.data.settings.recurringServiceDays.contains(weekday) },
                            set: { isOn in
                                store.updateSettings { settings in
                                    if isOn {
                                        if !settings.recurringServiceDays.contains(weekday) {
                                            settings.recurringServiceDays.append(weekday)
                                            settings.recurringServiceDays.sort()
                                        }
                                    } else if settings.recurringServiceDays.count > 1 {
                                        settings.recurringServiceDays.removeAll { $0 == weekday }
                                    }
                                }
                            }
                        ))
                    }
                    Text("Select the day(s) of your weekly service. At least one day must be selected.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Language") {
                    Picker("App Language", selection: Binding(
                        get: { store.data.settings.language },
                        set: { newValue in store.updateSettings { $0.language = newValue } }
                    )) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text("Language changes apply immediately on this phone.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("App Lock") {
                    Toggle("Require unlock on open", isOn: Binding(
                        get: { store.data.settings.appLockEnabled },
                        set: { newValue in store.updateSettings { $0.appLockEnabled = newValue } }
                    ))
                    SecureField("New PIN", text: $pin)
                        .keyboardType(.numberPad)
                    Button {
                        store.setPIN(pin)
                        pin = ""
                    } label: {
                        Label("Save PIN", systemImage: "key")
                    }
                }

                Section("Encrypted Backup") {
                    NavigationLink {
                        AdminHandoffGuideView()
                    } label: {
                        Label("Admin Handoff Guide", systemImage: "person.2.badge.gearshape")
                    }

                    SecureField("Backup password", text: $backupPassword)
                    Button {
                        prepareExport()
                    } label: {
                        Label("Export Backup", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        guard !backupPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                            store.errorMessage = store.localized("Enter the backup password before importing.")
                            return
                        }
                        isImporting = true
                    } label: {
                        Label("Import Backup", systemImage: "square.and.arrow.down")
                    }
                }

                Section("Data") {
                    LabeledContent("Servants", value: "\(store.data.servants.count)")
                    LabeledContent("Tasks", value: "\(store.data.tasks.count)")
                    LabeledContent("Schedules", value: "\(store.data.schedules.count)")
                    LabeledContent("Reminders", value: "\(store.data.reminders.count)")
                }
            }
            .navigationTitle("Settings")
            .fileExporter(
                isPresented: $isExporting,
                document: exportDocument,
                contentType: .debreMihretBackup,
                defaultFilename: backupFilename
            ) { result in
                switch result {
                case .success:
                    store.noticeMessage = store.localized("Backup exported.")
                case .failure(let error):
                    store.errorMessage = store.localized(error.localizedDescription)
                }
            }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.data, .debreMihretBackup]) { result in
                switch result {
                case .success(let url):
                    importBackup(from: url)
                case .failure(let error):
                    store.errorMessage = store.localized(error.localizedDescription)
                }
            }
        }
    }

    private func prepareExport() {
        do {
            exportDocument = BackupDocument(data: try store.exportBackup(password: backupPassword))
            isExporting = true
        } catch {
            store.errorMessage = store.localized(error.localizedDescription)
        }
    }

    private func importBackup(from url: URL) {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url)
            store.importBackup(data, password: backupPassword)
        } catch {
            store.errorMessage = store.localized(error.localizedDescription)
        }
    }
}

struct AdminHandoffGuideView: View {
    @EnvironmentObject private var store: SchedulerStore

    var body: some View {
        List {
            Section("What Admin Means") {
                Label("The active admin is the trusted organizer who can unlock the phone and this app.", systemImage: "iphone")
                Label("There is no cloud admin list because all Debre Mihret St Michael Church data stays on the device.", systemImage: "lock.shield")
            }

            Section("Current Organizer") {
                HandoffStepRow(number: 1, text: "Open Settings.")
                HandoffStepRow(number: 2, text: "Enter a backup password.")
                HandoffStepRow(number: 3, text: "Tap Export Backup.")
                HandoffStepRow(number: 4, text: "Send the backup file to the new organizer.")
                HandoffStepRow(number: 5, text: "Share the password separately.")
            }

            Section("New Organizer") {
                HandoffStepRow(number: 1, text: "Install \(store.data.settings.appDisplayName).")
                HandoffStepRow(number: 2, text: "Create a local app PIN on this phone.")
                HandoffStepRow(number: 3, text: "Open Settings and enter the backup password.")
                HandoffStepRow(number: 4, text: "Tap Import Backup and select the file.")
                HandoffStepRow(number: 5, text: "Check servants, tasks, schedules, and Telegram settings.")
            }

            Section("Important") {
                Label("A backup is a copy, not live sync. Choose one active admin phone after handoff.", systemImage: "arrow.triangle.branch")
                Label("The backup includes servant details and Telegram settings. Delete extra copies after import.", systemImage: "trash")
            }
        }
        .navigationTitle("Admin Handoff")
    }
}

struct HandoffStepRow: View {
    var number: Int
    var text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(.teal, in: Circle())

            Text(LocalizedStringKey(text))
                .font(.body)
        }
    }
}

struct RoleChecklist: View {
    @EnvironmentObject private var store: SchedulerStore
    @Binding var selection: [ServantRole]

    var body: some View {
        ForEach(ServantRole.allCases) { role in
            Button {
                if selection.contains(role) {
                    selection.removeAll { $0 == role }
                } else {
                    selection.append(role)
                }
            } label: {
                HStack {
                    Text(role.localizedName(store.language))
                    Spacer()
                    Image(systemName: selection.contains(role) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selection.contains(role) ? .teal : .secondary)
                }
            }
            .buttonStyle(.plain)
        }
    }
}

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.debreMihretBackup, .data] }
    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

extension UTType {
    static let debreMihretBackup = UTType(exportedAs: "org.church.servicescheduler.backup")
}

extension View {
    func alertMessages(store: SchedulerStore) -> some View {
        self
            .alert("Notice", isPresented: Binding(
                get: { store.noticeMessage != nil },
                set: { if !$0 { store.noticeMessage = nil } }
            )) {
                Button("OK", role: .cancel) { store.noticeMessage = nil }
            } message: {
                Text(LocalizedStringKey(store.noticeMessage ?? ""))
            }
            .alert("Error", isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { store.errorMessage = nil }
            } message: {
                Text(LocalizedStringKey(store.errorMessage ?? ""))
            }
    }
}
