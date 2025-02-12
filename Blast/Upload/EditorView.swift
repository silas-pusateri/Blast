@_spi(Unstable) @_spi(Internal) import IMGLYEditor
import IMGLYVideoEditor
import SwiftUI
import AVFoundation


struct EditorView: View {
    @Environment(\.dismiss) var dismiss
    let videoURL: URL
    let isSuggestMode: Bool
    let onSave: (URL, [String: Any]?) -> Void
    
    private let settings = EngineSettings(
        license: Secrets.licenseKey,
        userID: UUID().uuidString  // Generate unique user ID per session
    )
    
    init(videoURL: URL, isSuggestMode: Bool = false, onSave: @escaping (URL, [String: Any]?) -> Void) {
        self.videoURL = videoURL
        self.isSuggestMode = isSuggestMode
        self.onSave = onSave
    }
    
    init(video: Video, isSuggestMode: Bool = false, onSave: @escaping (URL, [String: Any]?) -> Void) {
        guard let url = URL(string: video.url) else {
            fatalError("Invalid video URL")
        }
        self.init(videoURL: url, isSuggestMode: isSuggestMode, onSave: onSave)
    }
    
    private func createMetadata(from outputURL: URL) -> [String: Any] {
        return [
            "editedAt": Date().timeIntervalSince1970,
            "originalURL": videoURL.absoluteString,
            "isEditedVersion": true
        ]
    }
    
    var editor: some View {
    VideoEditor(settings)
        .imgly.onCreate { engine in
            try await engine.scene.load(from: videoURL)
        }
        .imgly.onExport { engine, _ in
            if let outputURL = try? await engine.scene.export() {
                let metadata = createMetadata(from: outputURL)
                onSave(outputURL, metadata)
                dismiss()
            }
        }
    }

    
    var body: some View {
        NavigationView {
            editor
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarItems(
                    leading: Button("Cancel") {
                        dismiss()
                    },
                    trailing: EmptyView() // Export button is handled by VideoEditor
                )
        }
    }
}

#Preview {
    EditorView(
        videoURL: URL(string: "https://example.com/video.mp4")!,
        onSave: { _, _ in }
    )
}