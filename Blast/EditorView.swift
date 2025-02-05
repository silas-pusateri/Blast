import SwiftUI
import VideoEditorSDK
import ImglyKit

struct EditorView: View {
    @Environment(\.dismiss) var dismiss
    let videoURL: URL
    let onSave: (URL) -> Void
    
    var body: some View {
        VideoEditor(video: ImglyKit.Video(url: videoURL))
            .onDidSave { result in
                // The user exported a new video successfully
                print("Video saved at \(result.output.url.absoluteString)")
                onSave(result.output.url)
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