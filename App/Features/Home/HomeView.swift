import PhotosUI
import SenseCore
import SwiftData
import SwiftUI

enum HomeDestination: Hashable {
    case memories(query: String?)
    case memory(UUID)
    case similar(UUID)
    case reminders
    case settings
}

enum HomeSheet: Identifiable {
    case voice
    case text
    case review(CaptureDraft)
    case reminder(ReminderRequest)

    var id: String {
        switch self {
        case .voice: "voice"
        case .text: "text"
        case .review(let draft): "review-\(draft.id)"
        case .reminder(let request): "reminder-\(request.id)"
        }
    }
}

struct HomeView: View {
    @Environment(AppModel.self) private var app
    @Query(sort: \MemoryEntity.createdAt, order: .reverse) private var memories: [MemoryEntity]
    @Query(filter: #Predicate<ReminderEntity> { $0.isCompleted == false }, sort: \ReminderEntity.createdAt)
    private var openReminders: [ReminderEntity]

    @State private var path = NavigationPath()
    @State private var sheet: HomeSheet?
    @State private var showCamera = false
    @State private var showLook = false
    @State private var showPhotoPicker = false
    @State private var photoItem: PhotosPickerItem?
    @State private var processingMessage: String?
    @State private var error: Error?
    @State private var notice: String?

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    lookCard
                    captureGrid
                    if !openReminders.isEmpty {
                        remindersSection
                    }
                    recentSection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        path.append(HomeDestination.settings)
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel(String(localized: "Settings"))
                }
            }
            .navigationDestination(for: HomeDestination.self, destination: destination)
        }
        .overlay {
            if let processingMessage {
                ZStack {
                    Color.black.opacity(0.15).ignoresSafeArea()
                    ProcessingOverlay(message: processingMessage)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: processingMessage)
        .sheet(item: $sheet, content: sheetContent)
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in
                showCamera = false
                if let image {
                    capture(image: image, source: .camera)
                }
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showLook) {
            LiveLookView { image, text in
                showLook = false
                if let image {
                    capture(image: image, source: .live)
                } else if let text {
                    capture(text: text, source: .live)
                }
            }
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images, preferredItemEncoding: .compatible)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            photoItem = nil
            loadPhoto(item)
        }
        .onChange(of: app.openedMemoryID) { _, id in
            guard let id else { return }
            app.openedMemoryID = nil
            sheet = nil
            path = NavigationPath()
            path.append(HomeDestination.memory(id))
        }
        .errorAlert($error)
        .alert(
            String(localized: "SENSE"),
            isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })
        ) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(notice ?? "")
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: "SENSE")
                .font(.system(.largeTitle, design: .rounded, weight: .heavy))
                .tracking(4)
                .accessibilityAddTraits(.isHeader)
            Text("Capture something. SENSE understands it.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }

    private var lookCard: some View {
        Button(action: startLook) {
            HStack(spacing: 16) {
                Image(systemName: "viewfinder")
                    .font(.system(size: 30, weight: .semibold))
                    .frame(width: 56, height: 56)
                    .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("What's important here?")
                        .font(.headline)
                    Text("Point your camera at a sign, document or object.")
                        .font(.subheadline)
                        .opacity(0.85)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.headline)
                    .opacity(0.7)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(.white)
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint(String(localized: "Opens the camera and explains what it sees."))
    }

    private var captureGrid: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                Menu {
                    Button(action: startCamera) {
                        Label(String(localized: "Take Photo"), systemImage: "camera")
                    }
                    Button {
                        showPhotoPicker = true
                    } label: {
                        Label(String(localized: "Choose from Photos"), systemImage: "photo.on.rectangle")
                    }
                } label: {
                    CaptureTile(title: String(localized: "Camera"), symbol: "camera.fill", tint: .blue)
                }
                .accessibilityHint(String(localized: "Take a photo or choose one to understand."))

                Button {
                    sheet = .voice
                } label: {
                    CaptureTile(title: String(localized: "Voice"), symbol: "mic.fill", tint: .orange)
                }
                .accessibilityHint(String(localized: "Speak a note, a reminder or a question."))
            }
            GridRow {
                Button {
                    sheet = .text
                } label: {
                    CaptureTile(title: String(localized: "Text"), symbol: "text.cursor", tint: .purple)
                }
                .accessibilityHint(String(localized: "Type a note, a reminder or a question."))

                Button {
                    path.append(HomeDestination.memories(query: nil))
                } label: {
                    CaptureTile(title: String(localized: "Memories"), symbol: "square.stack.fill", tint: .green, badge: memories.isEmpty ? nil : memories.count)
                }
                .accessibilityHint(String(localized: "Browse and search what you've captured."))
            }
        }
        .buttonStyle(.plain)
    }

    private var remindersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: String(localized: "Upcoming"), actionTitle: String(localized: "See All")) {
                path.append(HomeDestination.reminders)
            }
            VStack(spacing: 0) {
                ForEach(openReminders.prefix(3)) { reminder in
                    ReminderRow(reminder: reminder)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    if reminder.id != openReminders.prefix(3).last?.id {
                        Divider().padding(.leading, 14)
                    }
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: String(localized: "Recent"), actionTitle: memories.isEmpty ? nil : String(localized: "See All")) {
                path.append(HomeDestination.memories(query: nil))
            }
            if memories.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Nothing captured yet")
                        .font(.headline)
                    Text("Try photographing a poster, a receipt or a document, or say “Remind me to call the lab tomorrow at 5.”")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                VStack(spacing: 0) {
                    ForEach(memories.prefix(5)) { memory in
                        NavigationLink(value: HomeDestination.memory(memory.id)) {
                            MemoryRow(memory: memory)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if memory.id != memories.prefix(5).last?.id {
                            Divider().padding(.leading, 80)
                        }
                    }
                }
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    // MARK: Navigation

    @ViewBuilder
    private func destination(_ destination: HomeDestination) -> some View {
        switch destination {
        case .memories(let query):
            MemoriesView(initialQuery: query ?? "")
        case .memory(let id):
            MemoryDetailView(memoryID: id)
        case .similar(let id):
            SimilarMemoriesView(memoryID: id)
        case .reminders:
            RemindersView()
        case .settings:
            SettingsView()
        }
    }

    @ViewBuilder
    private func sheetContent(_ sheet: HomeSheet) -> some View {
        switch sheet {
        case .voice:
            VoiceCaptureView { transcript in
                self.sheet = nil
                runCommand(transcript, source: .voice)
            }
        case .text:
            TextCaptureView { text in
                self.sheet = nil
                runCommand(text, source: .text)
            }
        case .review(let draft):
            CaptureReviewView(draft: draft) { saved in
                self.sheet = nil
                if let saved {
                    path.append(HomeDestination.memory(saved))
                }
            }
        case .reminder(let request):
            ReminderComposerView(request: request) { spec in
                try await app.reminders.create(title: spec.title, body: request.body, trigger: spec.trigger, memoryID: request.memoryID)
            } onClose: {
                self.sheet = nil
            }
        }
    }

    // MARK: Actions

    private func startCamera() {
        Task {
            do {
                guard UIImagePickerController.isSourceTypeAvailable(.camera) else { throw SenseError.cameraUnavailable }
                try await app.permissions.ensure(.camera)
                showCamera = true
            } catch {
                self.error = error
            }
        }
    }

    private func startLook() {
        Task {
            do {
                guard UIImagePickerController.isSourceTypeAvailable(.camera) else { throw SenseError.cameraUnavailable }
                try await app.permissions.ensure(.camera)
                showLook = true
            } catch {
                self.error = error
            }
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem) {
        Task {
            processingMessage = String(localized: "Reading photo…")
            do {
                guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                    throw SenseError.imageUnreadable
                }
                processingMessage = nil
                capture(image: image, source: .photo)
            } catch {
                processingMessage = nil
                self.error = error
            }
        }
    }

    private func capture(image: UIImage, source: CaptureSource) {
        let started = ContinuousClock.now
        Task {
            processingMessage = String(localized: "Understanding…")
            defer { processingMessage = nil }
            do {
                let draft = try await app.pipeline.process(image: image, source: source)
                await settlePresentation(since: started)
                sheet = .review(draft)
            } catch {
                self.error = error
            }
        }
    }

    private func capture(text: String, source: CaptureSource) {
        let started = ContinuousClock.now
        Task {
            processingMessage = String(localized: "Understanding…")
            defer { processingMessage = nil }
            do {
                let draft = try await app.pipeline.process(text: text, source: source)
                await settlePresentation(since: started)
                sheet = .review(draft)
            } catch {
                self.error = error
            }
        }
    }

    private func runCommand(_ text: String, source: CaptureSource) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let started = ContinuousClock.now
        Task {
            processingMessage = String(localized: "Understanding…")
            defer { processingMessage = nil }
            do {
                let outcome = try await app.handle(command: trimmed, source: source)
                await settlePresentation(since: started)
                switch outcome {
                case .review(let draft):
                    sheet = .review(draft)
                case .reminder(let request):
                    sheet = .reminder(request)
                case .search(let query):
                    path.append(HomeDestination.memories(query: query))
                case .similar(let id):
                    path.append(HomeDestination.similar(id))
                case .look:
                    startLook()
                case .message(let message):
                    notice = message
                }
            } catch {
                self.error = error
            }
        }
    }

    private func settlePresentation(since start: ContinuousClock.Instant) async {
        let remaining = Duration.milliseconds(450) - (ContinuousClock.now - start)
        if remaining > .zero {
            try? await Task.sleep(for: remaining)
        }
    }
}

struct CaptureTile: View {
    let title: String
    let symbol: String
    let tint: Color
    var badge: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                Spacer()
                if let badge {
                    Text(badge, format: .number)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}
