import SwiftUI
import VideoEditorSDK
import ImglyKit
import AVFoundation

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
    
    private func moveToDocuments(from tempURL: URL) -> URL? {
        let fileManager = FileManager.default
        
        // Get documents directory
        guard let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("❌ [EditorView] Could not get documents directory")
            return nil
        }
        
        // Create a videos subdirectory if it doesn't exist
        let videosDirectory = documentsPath.appendingPathComponent("EditedVideos", isDirectory: true)
        do {
            try fileManager.createDirectory(at: videosDirectory, withIntermediateDirectories: true, attributes: nil)
            
            // Create unique filename with timestamp to avoid conflicts
            let timestamp = Int(Date().timeIntervalSince1970)
            let filename = "edited_video_\(timestamp)_\(UUID().uuidString).mp4"
            let destinationURL = videosDirectory.appendingPathComponent(filename)
            
            print("📝 [EditorView] Moving edited video from: \(tempURL.path)")
            print("📝 [EditorView] Moving edited video to: \(destinationURL.path)")
            
            // Remove any existing file
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            
            // Copy the file instead of moving it
            try fileManager.copyItem(at: tempURL, to: destinationURL)
            
            // Verify file exists and is readable
            guard fileManager.fileExists(atPath: destinationURL.path) else {
                print("❌ [EditorView] File does not exist after copy")
                return nil
            }
            
            guard fileManager.isReadableFile(atPath: destinationURL.path) else {
                print("❌ [EditorView] File is not readable after copy")
                return nil
            }
            
            // Get and log file attributes
            if let attributes = try? fileManager.attributesOfItem(atPath: destinationURL.path) {
                let fileSize = attributes[.size] as? UInt64 ?? 0
                print("✅ [EditorView] Successfully copied edited video. Size: \(fileSize) bytes")
            }
            
            return destinationURL
        } catch {
            print("❌ [EditorView] Failed to handle edited video: \(error)")
            return nil
        }
    }
    
    var body: some View {
        VideoEditor(video: ImglyKit.Video(url: videoURL))
            .onDidSave { result in
                print("✅ [EditorView] Video editor completed save")
                let metadata = createMetadata(from: result)
                
                // Move the file to a permanent location
                if let permanentURL = moveToDocuments(from: result.output.url) {
                    print("✅ [EditorView] Video saved at \(permanentURL.absoluteString)")
                    
                    // Ensure the video file is ready before calling onSave
                    let asset = AVURLAsset(url: permanentURL)
                    Task {
                        do {
                            _ = try await asset.load(.duration)
                            _ = try await asset.load(.tracks)
                            
                            await MainActor.run {
                                onSave(permanentURL, metadata)
                                dismiss()
                            }
                        } catch {
                            print("❌ [EditorView] Failed to verify edited video: \(error)")
                            // If verification fails, try to use the original temp URL as fallback
                            await MainActor.run {
                                onSave(result.output.url, metadata)
                                dismiss()
                            }
                        }
                    }
                } else {
                    print("❌ [EditorView] Failed to move video to permanent location")
                    // Still try to use the temporary URL if move failed
                    onSave(result.output.url, metadata)
                    dismiss()
                }
            }
            .onDidCancel {
                print("ℹ️ [EditorView] User cancelled editing")
                dismiss()
            }
            .onDidFail { error in
                print("❌ [EditorView] Editor failed with error: \(error.localizedDescription)")
                dismiss()
            }
            .ignoresSafeArea()
    }
} 