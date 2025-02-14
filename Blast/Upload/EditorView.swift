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
        userID: "<your unique user id>"
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
            "originalURL": videoURL.absoluteString
        ]
    }
    
    var editor: some View {
        VideoEditor(settings)
    }
    
    var body: some View {
        ModalEditor {
            editor
        }
    }
}