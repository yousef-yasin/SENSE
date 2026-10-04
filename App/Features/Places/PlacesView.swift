import SwiftData
import SwiftUI

struct PlacesView: View {
    @Environment(AppModel.self) private var app
    @Query(sort: \PlaceEntity.name) private var places: [PlaceEntity]
    @State private var showSearch = false
    @State private var error: Error?

    var body: some View {
        List {
            ForEach(places) { place in
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.name)
                    if !place.aliases.isEmpty {
                        Text(place.aliases.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { offsets in
                do {
                    for index in offsets {
                        try app.places.delete(places[index])
                    }
                } catch {
                    self.error = error
                }
            }
        }
        .overlay {
            if places.isEmpty {
                ContentUnavailableView(
                    String(localized: "No Saved Places"),
                    systemImage: "mappin.slash",
                    description: Text("Places you choose for reminders, like “university” or “home”, appear here so SENSE recognizes them next time.")
                )
            }
        }
        .navigationTitle(String(localized: "Saved Places"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showSearch = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(String(localized: "Add Place"))
            }
        }
        .sheet(isPresented: $showSearch) {
            PlaceSearchView(initialQuery: "") { name, coordinate in
                do {
                    try app.places.add(name: name, alias: nil, coordinate: coordinate)
                } catch {
                    self.error = error
                }
            }
        }
        .errorAlert($error)
    }
}
