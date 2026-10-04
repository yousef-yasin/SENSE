import SwiftUI

struct TextCaptureView: View {
    let onFinish: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var isFocused: Bool

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                TextField(
                    String(localized: "Write a note, a reminder or a question"),
                    text: $text,
                    axis: .vertical
                )
                .font(.title3)
                .lineLimit(4...12)
                .focused($isFocused)
                .submitLabel(.done)

                Text("SENSE works out whether this is something to remember, a reminder, or a question about your memories.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding(20)
            .navigationTitle(String(localized: "Text"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { onFinish(trimmed) }
                        .disabled(trimmed.isEmpty)
                }
            }
            .onAppear { isFocused = true }
        }
        .presentationDetents([.medium, .large])
    }
}
