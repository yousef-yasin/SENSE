import CoreLocation
import SenseCore
import SwiftUI

struct ReminderComposerView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case time
        case arriving
        case leaving

        var id: String { rawValue }

        var title: String {
            switch self {
            case .time: String(localized: "Time")
            case .arriving: String(localized: "Arriving")
            case .leaving: String(localized: "Leaving")
            }
        }
    }

    let request: ReminderRequest
    let onSubmit: (ReminderSpec) async throws -> Void
    let onClose: () -> Void

    @Environment(AppModel.self) private var app
    @State private var title: String
    @State private var mode: Mode
    @State private var date: Date
    @State private var spokenPlace: String
    @State private var selectedPlace: PlaceEntity?
    @State private var places: [PlaceEntity] = []
    @State private var showSearch = false
    @State private var isSubmitting = false
    @State private var error: Error?

    init(request: ReminderRequest, onSubmit: @escaping (ReminderSpec) async throws -> Void, onClose: @escaping () -> Void) {
        self.request = request
        self.onSubmit = onSubmit
        self.onClose = onClose
        _title = State(initialValue: request.draft.title)
        let nextHour = Calendar.current.nextDate(after: Date(), matching: DateComponents(minute: 0), matchingPolicy: .nextTime) ?? Date().addingTimeInterval(3600)
        switch request.draft.timing {
        case .at(let date):
            _mode = State(initialValue: .time)
            _date = State(initialValue: max(date, Date().addingTimeInterval(60)))
            _spokenPlace = State(initialValue: "")
        case .arriving(let place):
            _mode = State(initialValue: .arriving)
            _date = State(initialValue: nextHour)
            _spokenPlace = State(initialValue: place)
        case .leaving(let place):
            _mode = State(initialValue: .leaving)
            _date = State(initialValue: nextHour)
            _spokenPlace = State(initialValue: place)
        case .unspecified:
            _mode = State(initialValue: .time)
            _date = State(initialValue: nextHour)
            _spokenPlace = State(initialValue: "")
        }
    }

    private var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (mode == .time ? date > Date() : selectedPlace != nil)
            && !isSubmitting
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: "What should SENSE remind you about?"), text: $title, axis: .vertical)
                    if let memoryTitle = request.memoryTitle {
                        Label {
                            Text("About “\(memoryTitle)”")
                        } icon: {
                            Image(systemName: "link")
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Picker(String(localized: "When"), selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                if mode == .time {
                    Section {
                        DatePicker(String(localized: "Date"), selection: $date, in: Date()...)
                            .datePickerStyle(.graphical)
                    }
                } else {
                    placeSection
                }
            }
            .navigationTitle(String(localized: "Reminder"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel"), action: onClose)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Add"), action: submit)
                        .disabled(!canSubmit)
                }
            }
            .task(id: mode) { reloadPlaces() }
            .sheet(isPresented: $showSearch) {
                PlaceSearchView(initialQuery: spokenPlace) { name, coordinate in
                    do {
                        let place = try app.places.add(name: name, alias: spokenPlace, coordinate: coordinate)
                        reloadPlaces()
                        selectedPlace = place
                    } catch {
                        self.error = error
                    }
                }
            }
        }
        .errorAlert($error)
    }

    private var placeSection: some View {
        Section {
            ForEach(places) { place in
                Button {
                    selectedPlace = place
                } label: {
                    HStack {
                        Label(place.name, systemImage: "mappin.circle")
                            .foregroundStyle(.primary)
                        Spacer()
                        if selectedPlace?.id == place.id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                                .accessibilityLabel(String(localized: "Selected"))
                        }
                    }
                }
            }
            Button {
                showSearch = true
            } label: {
                Label(
                    spokenPlace.isEmpty ? String(localized: "Find a place…") : String(localized: "Find “\(spokenPlace)”…"),
                    systemImage: "magnifyingglass"
                )
            }
        } header: {
            Text("Place")
        } footer: {
            Text(mode == .arriving
                 ? String(localized: "iOS watches for this place on SENSE's behalf and only notifies the app when you arrive. SENSE doesn't track or store your movements.")
                 : String(localized: "iOS watches for this place on SENSE's behalf and only notifies the app when you leave. SENSE doesn't track or store your movements."))
        }
    }

    private func reloadPlaces() {
        places = app.places.all()
        if selectedPlace == nil, !spokenPlace.isEmpty {
            selectedPlace = app.places.match(spokenPlace)
        }
    }

    private func submit() {
        let trigger: ReminderTrigger
        switch mode {
        case .time:
            trigger = .date(date)
        case .arriving, .leaving:
            guard let place = selectedPlace else { return }
            trigger = .region(place.region, onArrival: mode == .arriving)
        }
        let spec = ReminderSpec(title: title.trimmingCharacters(in: .whitespacesAndNewlines), trigger: trigger)
        isSubmitting = true
        Task {
            defer { isSubmitting = false }
            do {
                try await onSubmit(spec)
                onClose()
            } catch {
                self.error = error
            }
        }
    }
}

struct PlaceSearchView: View {
    let initialQuery: String
    let onSelect: (String, CLLocationCoordinate2D) -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [PlaceResult] = []
    @State private var isSearching = false
    @State private var error: Error?

    struct PlaceResult: Identifiable {
        let id = UUID()
        var name: String
        var subtitle: String
        var coordinate: CLLocationCoordinate2D
    }

    var body: some View {
        NavigationStack {
            List {
                if app.location.isAuthorized {
                    Section {
                        Button {
                            useCurrentLocation()
                        } label: {
                            Label(String(localized: "Use my current location"), systemImage: "location.fill")
                        }
                    }
                }
                Section {
                    ForEach(results) { result in
                        Button {
                            onSelect(result.name, result.coordinate)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.name).foregroundStyle(.primary)
                                if !result.subtitle.isEmpty {
                                    Text(result.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .overlay {
                if isSearching {
                    ProgressView()
                } else if results.isEmpty && !query.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: String(localized: "Search places"))
            .onSubmit(of: .search) { Task { await search() } }
            .navigationTitle(String(localized: "Choose a Place"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
            }
            .task {
                query = initialQuery
                if !initialQuery.isEmpty { await search() }
            }
        }
        .errorAlert($error)
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isSearching = true
        defer { isSearching = false }
        do {
            var near: CLLocation?
            if app.location.isAuthorized {
                near = try? await app.location.currentLocation(timeout: .seconds(5))
            }
            let items = try await app.location.searchPlaces(matching: text, near: near)
            results = items.map { item in
                PlaceResult(
                    name: item.name ?? text,
                    subtitle: item.placemark.title ?? "",
                    coordinate: item.placemark.coordinate
                )
            }
        } catch {
            results = []
            self.error = error
        }
    }

    private func useCurrentLocation() {
        Task {
            do {
                let location = try await app.location.currentLocation()
                let name = await app.location.reverseGeocode(location) ?? (initialQuery.isEmpty ? String(localized: "Current Location") : initialQuery.capitalized)
                onSelect(name, location.coordinate)
                dismiss()
            } catch {
                self.error = error
            }
        }
    }
}
