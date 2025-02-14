import SwiftUI
import AVKit
import FirebaseAuth

struct VideoChangesView: View {
    let video: Video
    @EnvironmentObject private var videoViewModel: VideoViewModel
    @StateObject private var changesViewModel: ChangesViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingSuggestChanges = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    init(video: Video, videoViewModel: VideoViewModel) {
        self.video = video
        _changesViewModel = StateObject(wrappedValue: ChangesViewModel(videoViewModel: videoViewModel))
    }
    
    var body: some View {
        NavigationView {
            Group {
                if changesViewModel.changes.isEmpty {
                    VStack(spacing: 20) {
                        ContentUnavailableView(
                            "No Changes",
                            systemImage: "pencil.slash",
                            description: Text("No one has suggested any changes to this video yet.")
                        )
                        
                        Button(action: {
                            showingSuggestChanges = true
                        }) {
                            Label("Suggest Changes", systemImage: "pencil.circle.fill")
                                .font(.headline)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        if video.userId == Auth.auth().currentUser?.uid {
                            Section {
                                Button(action: {
                                    showingSuggestChanges = true
                                }) {
                                    Label("Suggest New Changes", systemImage: "pencil.circle.fill")
                                }
                            }
                        }
                        
                        Section {
                            ForEach(changesViewModel.changes) { change in
                                ChangeRowView(
                                    change: change,
                                    isOwner: video.userId == Auth.auth().currentUser?.uid,
                                    onAccept: {
                                        handleAccept(change)
                                    },
                                    onReject: {
                                        handleReject(change)
                                    },
                                    onPreview: {
                                        // Preview is handled by ChangeRowView
                                    }
                                )
                            }
                        } header: {
                            Text("Suggested Changes")
                        }
                    }
                }
            }
            .navigationTitle("Video Changes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !changesViewModel.changes.isEmpty {
                        Button(action: {
                            showingSuggestChanges = true
                        }) {
                            Image(systemName: "plus.circle.fill")
                        }
                    }
                }
                
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .overlay {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.ultraThinMaterial)
                }
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") {
                    errorMessage = nil
                }
            } message: {
                if let error = errorMessage {
                    Text(error)
                }
            }
        }
        .sheet(isPresented: $showingSuggestChanges) {
            SuggestChangesView(video: video, videoViewModel: videoViewModel)
        }
        .task {
            do {
                try await changesViewModel.fetchChanges(videoId: video.id)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
    
    private func handleAccept(_ change: Change) {
        isLoading = true
        Task {
            do {
                try await changesViewModel.acceptChange(change)
                isLoading = false
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
    
    private func handleReject(_ change: Change) {
        isLoading = true
        Task {
            do {
                try await changesViewModel.rejectChange(change)
                isLoading = false
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
} 