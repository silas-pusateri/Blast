import SwiftUI
import AVKit

struct SuggestChangesView: View {
    let video: Video
    @EnvironmentObject private var videoViewModel: VideoViewModel
    @StateObject private var changesViewModel: ChangesViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var description = ""
    @State private var showingEditor = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var editedVideoURL: URL?
    @State private var editMetadata: [String: Any]?
    @State private var isUploading = false
    
    init(video: Video, videoViewModel: VideoViewModel) {
        self.video = video
        _changesViewModel = StateObject(wrappedValue: ChangesViewModel(videoViewModel: videoViewModel))
    }
    
    private func uploadAndSubmit() async throws {
        guard let editedURL = editedVideoURL else {
            // If no video edits, just submit the description
            try await changesViewModel.createChange(
                videoId: video.id,
                description: description
            )
            return
        }
        
        let timestamp = Int(Date().timeIntervalSince1970)
        let path = "videos/\(UUID().uuidString)_\(timestamp).mp4"
        
        let downloadURL = try await VideoUploader.shared.uploadVideo(from: editedURL, to: path)
        print("📹 [SuggestChangesView] Edited video download URL:", downloadURL)
        
        // Verify we have a valid HTTPS URL
        guard let url = URL(string: downloadURL),
              url.scheme == "https",
              url.host?.contains("firebasestorage.googleapis.com") == true else {
            throw NSError(domain: "SuggestChangesView",
                         code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Invalid download URL format"])
        }
        
        try await changesViewModel.createChange(
            videoId: video.id,
            description: description,
            editUrl: downloadURL,
            diffMetadata: editMetadata
        )
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Original Video")) {
                    if let url = URL(string: video.url) {
                        VideoPlayer(player: AVPlayer(url: url))
                            .frame(height: 200)
                    }
                }
                
                if let editedURL = editedVideoURL {
                    Section(header: Text("Edited Preview")) {
                        VideoPlayer(player: AVPlayer(url: editedURL))
                            .frame(height: 200)
                    }
                }
                
                Section(header: Text("Change Description")) {
                    TextEditor(text: $description)
                        .frame(height: 100)
                }
                
                Section {
                    Button(action: {
                        showingEditor = true
                    }) {
                        Label(editedVideoURL == nil ? "Edit Video" : "Edit Again", 
                              systemImage: editedVideoURL == nil ? "pencil" : "pencil.circle")
                    }
                }
                
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Suggest Changes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Submit") {
                        submitChanges()
                    }
                    .disabled(description.isEmpty || isSubmitting || isUploading)
                }
            }
            .overlay {
                if isUploading {
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()
                    
                    VStack {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        Text("Uploading edited video...")
                            .foregroundColor(.white)
                            .padding(.top)
                    }
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            EditorView(video: video, isSuggestMode: true) { url, metadata in
                self.editedVideoURL = url
                self.editMetadata = metadata
            }
            .interactiveDismissDisabled()
        }
    }
    
    private func submitChanges() {
        guard !description.isEmpty else { return }
        
        isSubmitting = true
        isUploading = editedVideoURL != nil
        errorMessage = nil
        
        Task {
            do {
                try await uploadAndSubmit()
                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSubmitting = false
                    isUploading = false
                }
            }
        }
    }
}