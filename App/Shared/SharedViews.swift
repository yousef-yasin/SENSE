import SenseCore
import SwiftUI

struct ErrorAlert: ViewModifier {
    @Binding var error: Error?
    @Environment(AppModel.self) private var app

    func body(content: Content) -> some View {
        content.alert(
            String(localized: "Something went wrong"),
            isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } }),
            presenting: error
        ) { failure in
            if case .permissionDenied? = failure as? SenseError {
                Button(String(localized: "Open Settings")) { app.permissions.openSystemSettings() }
            }
            Button(String(localized: "OK"), role: .cancel) {}
        } message: { failure in
            Text(failure.localizedDescription)
        }
    }
}

extension View {
    func errorAlert(_ error: Binding<Error?>) -> some View {
        modifier(ErrorAlert(error: error))
    }
}

struct MemoryThumbnail: View {
    let memory: MemoryEntity
    var size: CGFloat = 52

    @Environment(AppModel.self) private var app
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(memory.kind.tint.opacity(0.15))
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: memory.kind.symbol)
                    .font(.title3)
                    .foregroundStyle(memory.kind.tint)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityHidden(true)
        .task(id: memory.imageFileName) {
            guard let name = memory.imageFileName else { return }
            image = await app.memories.images.thumbnail(name, size: size * 3)
        }
    }
}

struct MemoryRow: View {
    let memory: MemoryEntity

    var body: some View {
        HStack(spacing: 14) {
            MemoryThumbnail(memory: memory)
            VStack(alignment: .leading, spacing: 3) {
                Text(memory.displayTitle)
                    .font(.headline)
                    .lineLimit(2)
                if !memory.summary.isEmpty {
                    Text(memory.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                HStack(spacing: 6) {
                    Text(memory.kind.title)
                    Text(verbatim: "·")
                    Text(memory.createdAt, format: .relative(presentation: .named))
                    if let place = memory.placeName {
                        Text(verbatim: "·")
                        Text(place).lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

struct SectionHeader: View {
    let title: String
    var actionTitle: String?
    var action: () -> Void = {}

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let actionTitle {
                Button(actionTitle, action: action)
                    .font(.subheadline)
            }
        }
    }
}

struct ProcessingOverlay: View {
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
            Text(message)
                .font(.headline)
        }
        .padding(28)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
