import SwiftUI
import AVKit
import FirebaseAuth

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
    
    private var isSelfEdit: Bool {
        video.userId == Auth.auth().currentUser?.uid
    }
    
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
        let path = "edited_videos/\(UUID().uuidString)_\(timestamp).mp4"
        
        let downloadURL = try await VideoUploader.shared.uploadVideo(from: editedURL, to: path)
        
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
                
                Section(header: Text(isSelfEdit ? "Change Description (for version history)" : "Change Description")) {
                    TextEditor(text: $description)
                        .frame(height: 100)
                        .overlay(
                            Group {
                                if description.isEmpty {
                                    Text(isSelfEdit ? "Describe what you changed in this version..." : "Explain your suggested changes...")
                                        .foregroundColor(.gray)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 8)
                                }
                            },
                            alignment: .topLeading
                        )
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
            .navigationTitle(isSelfEdit ? "Update Video" : "Suggest Changes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isSelfEdit ? "Create Update" : "Submit") {
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