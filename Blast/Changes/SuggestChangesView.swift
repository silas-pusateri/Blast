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
            ScrollView {
                VStack(spacing: 20) {
                    // Original Video
                    VStack(alignment: .leading) {
                        Text("Original Video")
                            .font(.headline)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                        
                        if let url = URL(string: video.url) {
                            VideoPlayer(player: AVPlayer(url: url))
                                .aspectRatio(9/16, contentMode: .fit)
                                .frame(maxWidth: .infinity)
                                .cornerRadius(12)
                                .padding(.horizontal)
                        }
                    }
                    
                    // Edited Preview
                    if let editedURL = editedVideoURL {
                        VStack(alignment: .leading) {
                            Text("Edited Preview")
                                .font(.headline)
                                .foregroundColor(.secondary)
                                .padding(.horizontal)
                            
                            VideoPlayer(player: AVPlayer(url: editedURL))
                                .aspectRatio(9/16, contentMode: .fit)
                                .frame(maxWidth: .infinity)
                                .cornerRadius(12)
                                .padding(.horizontal)
                        }
                    }
                    
                    // Edit Video Button
                    Button(action: {
                        showingEditor = true
                    }) {
                        Label(editedVideoURL == nil ? "Edit Video" : "Edit Again", 
                              systemImage: editedVideoURL == nil ? "pencil" : "pencil.circle")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    
                    // Change Description
                    VStack(alignment: .leading) {
                        Text("Change Description")
                            .font(.headline)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                        
                        TextEditor(text: $description)
                            .frame(height: 100)
                            .padding(8)
                            .background(Color(UIColor.systemGray6))
                            .cornerRadius(8)
                            .padding(.horizontal)
                    }
                    
                    if let error = errorMessage {
                        Text(error)
                            .foregroundColor(.red)
                            .padding(.horizontal)
                    }
                }
                .padding(.vertical)
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