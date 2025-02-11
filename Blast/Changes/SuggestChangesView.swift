import SwiftUI
import AVKit

struct SuggestChangesView: View {
    let video: Video
    @EnvironmentObject private var videoViewModel: VideoViewModel
    @StateObject private var changesViewModel: ChangesViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var description = ""
    @State private var isEditing = false
    @State private var showingEditor = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    
    init(video: Video, videoViewModel: VideoViewModel) {
        self.video = video
        _changesViewModel = StateObject(wrappedValue: ChangesViewModel(videoViewModel: videoViewModel))
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
                
                Section(header: Text("Change Description")) {
                    TextEditor(text: $description)
                        .frame(height: 100)
                }
                
                Section {
                    Button(action: {
                        showingEditor = true
                    }) {
                        Label("Edit Video", systemImage: "pencil")
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
                    .disabled(description.isEmpty || isSubmitting)
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            EditorView(video: video, isSuggestMode: true) { editUrl, metadata in
                // Handle edited video URL and metadata
                Task {
                    do {
                        try await changesViewModel.createChange(
                            videoId: video.id,
                            description: description,
                            editUrl: editUrl.absoluteString,
                            diffMetadata: metadata
                        )
                        dismiss()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }
    
    private func submitChanges() {
        guard !description.isEmpty else { return }
        
        isSubmitting = true
        errorMessage = nil
        
        // If no edits were made, just submit the description
        if !isEditing {
            Task {
                do {
                    try await changesViewModel.createChange(
                        videoId: video.id,
                        description: description
                    )
                    dismiss()
                } catch {
                    errorMessage = error.localizedDescription
                }
                isSubmitting = false
            }
        }
    }
} 