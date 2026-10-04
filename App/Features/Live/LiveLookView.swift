import SwiftUI
import VisionKit

struct LiveLookView: View {
    let onFinish: (UIImage?, String?) -> Void

    @State private var scanner = LiveScannerModel()
    @State private var isCapturing = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if LiveScannerModel.isSupported {
                LiveScannerView(model: scanner)
                    .ignoresSafeArea()
            } else {
                unsupported
            }
        }
        .overlay(alignment: .topLeading) {
            Button {
                onFinish(nil, nil)
            } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .padding(12)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel(String(localized: "Close"))
            .padding()
        }
        .overlay(alignment: .bottom) {
            if LiveScannerModel.isSupported {
                controls
            }
        }
        .preferredColorScheme(.dark)
    }

    private var controls: some View {
        VStack(spacing: 14) {
            Text(scanner.visibleText.isEmpty
                 ? String(localized: "Point at text, a sign or an object")
                 : String(localized: "Seeing \(scanner.visibleText.count) pieces of text"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.updatesFrequently)

            Button {
                capture()
            } label: {
                Label(String(localized: "What's important here?"), systemImage: "sparkles")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isCapturing)
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding()
    }

    private var unsupported: some View {
        ContentUnavailableView {
            Label(String(localized: "Live view isn't available"), systemImage: "viewfinder")
        } description: {
            Text("This iPhone doesn't support live text scanning. You can still take a photo and SENSE will understand it.")
        } actions: {
            Button(String(localized: "Close")) { onFinish(nil, nil) }
        }
    }

    private func capture() {
        isCapturing = true
        Task {
            let photo = await scanner.capturePhoto()
            let text = scanner.visibleText.joined(separator: "\n")
            isCapturing = false
            onFinish(photo, text.isEmpty ? nil : text)
        }
    }
}

@MainActor
@Observable
final class LiveScannerModel {
    private(set) var visibleText: [String] = []
    @ObservationIgnored weak var controller: DataScannerViewController?

    static var isSupported: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func update(with items: [RecognizedItem]) {
        visibleText = items.compactMap { item in
            switch item {
            case .text(let text): text.transcript
            case .barcode(let code): code.payloadStringValue
            @unknown default: nil
            }
        }
    }

    func capturePhoto() async -> UIImage? {
        guard let controller else { return nil }
        return try? await controller.capturePhoto()
    }
}

private struct LiveScannerView: UIViewControllerRepresentable {
    let model: LiveScannerModel

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.text(), .barcode()],
            qualityLevel: .balanced,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        model.controller = controller
        return controller
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        if !controller.isScanning {
            try? controller.startScanning()
        }
    }

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let model: LiveScannerModel

        init(model: LiveScannerModel) {
            self.model = model
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            model.update(with: allItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            model.update(with: allItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didRemove removedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            model.update(with: allItems)
        }
    }
}
