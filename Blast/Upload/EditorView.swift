import SwiftUI
import VideoEditorSDK
import ImglyKit

struct EditorView: View {
    @Environment(\.dismiss) var dismiss
    let videoURL: URL
    let isSuggestMode: Bool
    let onSave: (URL, [String: Any]?) -> Void
    
    init(videoURL: URL, isSuggestMode: Bool = false, onSave: @escaping (URL, [String: Any]?) -> Void) {
        self.videoURL = videoURL
        self.isSuggestMode = isSuggestMode
        self.onSave = onSave
    }
    
    // Convenience initializer for Video type
    init(video: Video, isSuggestMode: Bool = false, onSave: @escaping (URL, [String: Any]?) -> Void) {
        guard let url = URL(string: video.url) else {
            fatalError("Invalid video URL")
        }
        self.init(videoURL: url, isSuggestMode: isSuggestMode, onSave: onSave)
    }
    
    private func createMetadata(from result: VideoEditorResult) -> [String: Any] {
        // For now, we'll just store basic metadata since we can't access the detailed edit information
        let metadata: [String: Any] = [
            "editedAt": Date().timeIntervalSince1970,
            "originalURL": videoURL.absoluteString
        ]
        return metadata
    }
    
    var body: some View {
        VideoEditor(video: ImglyKit.Video(url: videoURL))
            .onDidSave { result in
                let metadata = createMetadata(from: result)
                print("Video saved at \(result.output.url.absoluteString)")
                onSave(result.output.url, metadata)
                dismiss()
            }
            .onDidCancel {
                // The user tapped on the cancel button
                dismiss()
            }
            .onDidFail { error in
                // There was an error generating the video
                print("Editor failed with error: \(error.localizedDescription)")
                dismiss()
            }
            .ignoresSafeArea()
    }
} 