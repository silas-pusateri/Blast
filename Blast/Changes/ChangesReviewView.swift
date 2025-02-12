import SwiftUI
import AVKit
import FirebaseAuth

struct ChangesReviewView: View {
    let video: Video
    @EnvironmentObject private var videoViewModel: VideoViewModel
    @StateObject private var changesViewModel: ChangesViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedChange: Change?
    @State private var showingPreview = false
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var showingSuggestChanges = false
    
    init(video: Video, videoViewModel: VideoViewModel) {
        self.video = video
        _changesViewModel = StateObject(wrappedValue: ChangesViewModel(videoViewModel: videoViewModel))
    }
    
    var body: some View {
        NavigationView {
            Group {
                if changesViewModel.changes.isEmpty {
                    ContentUnavailableView(
                        "No Changes",
                        systemImage: "pencil.slash",
                        description: Text("No one has suggested any changes to this video yet.")
                    )
                } else {
                    List {
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
                                    selectedChange = change
                                    showingPreview = true
                                }
                            )
                        }
                    }
                }
            }
            .navigationTitle("Suggested Changes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if video.userId == Auth.auth().currentUser?.uid {
                        Button("Suggest Changes") {
                            showingSuggestChanges = true
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
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
        .fullScreenCover(isPresented: $showingPreview) {
            if let change = selectedChange {
                ChangePreviewView(change: change)
            }
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
                // Refresh the feed to show the updated video
                await videoViewModel.fetchVideos(isRefresh: true)
                await MainActor.run {
                    isLoading = false
                    dismiss() // Dismiss after successful update
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
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

struct ChangeRowView: View {
    let change: Change
    let isOwner: Bool
    let onAccept: () -> Void
    let onReject: () -> Void
    let onPreview: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(change.description)
                .font(.body)
            
            HStack {
                Text(change.timestamp, style: .relative)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if change.status == .open && isOwner {
                    Button("Accept") {
                        onAccept()
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button("Reject", role: .destructive) {
                        onReject()
                    }
                    .buttonStyle(.bordered)
                } else {
                    Text(change.status.rawValue.capitalized)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(statusColor.opacity(0.2))
                        .foregroundColor(statusColor)
                        .clipShape(Capsule())
                }
            }
            
            if change.editUrl != nil {
                Button {
                    onPreview()
                } label: {
                    Label("Preview Changes", systemImage: "play.circle.fill")
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }
    
    private var statusColor: Color {
        switch change.status {
        case .open:
            return .blue
        case .accepted:
            return .green
        case .rejected:
            return .red
        }
    }
}

struct ChangePreviewView: View {
    let change: Change
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var errorMessage: String?
    @State private var isLoading = true
    
    var body: some View {
        NavigationView {
            Group {
                if let editUrl = change.editUrl,
                   let url = URL(string: editUrl) {
                    if let player = player {
                        VideoPlayer(player: player)
                            .ignoresSafeArea()
                            .onAppear {
                                player.play()
                            }
                            .onDisappear {
                                player.pause()
                            }
                    } else {
                        ProgressView("Loading video...")
                    }
                } else {
                    ContentUnavailableView(
                        "No Preview",
                        systemImage: "video.slash",
                        description: Text("This change doesn't have a video preview available.")
                    )
                }
            }
            .navigationTitle("Change Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        player?.pause()
                        player = nil
                        dismiss()
                    }
                }
            }
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") {
                    errorMessage = nil
                    dismiss()
                }
            } message: {
                if let error = errorMessage {
                    Text(error)
                }
            }
            .task {
                if let editUrl = change.editUrl,
                   let url = URL(string: editUrl) {
                    let asset = AVURLAsset(url: url)
                    
                    do {
                        // Load duration and tracks to ensure asset is playable
                        _ = try await asset.load(.duration)
                        let tracks = try await asset.load(.tracks)
                        
                        // Verify we have video tracks
                        guard tracks.contains(where: { $0.mediaType == .video }) else {
                            throw NSError(domain: "VideoPreview", code: -1, 
                                        userInfo: [NSLocalizedDescriptionKey: "Invalid video format"])
                        }
                        
                        // Create player item with settings for better playback
                        let playerItem = AVPlayerItem(asset: asset)
                        playerItem.preferredForwardBufferDuration = 5
                        
                        // Create and configure player
                        let newPlayer = AVPlayer(playerItem: playerItem)
                        newPlayer.automaticallyWaitsToMinimizeStalling = true
                        
                        await MainActor.run {
                            self.player = newPlayer
                            self.isLoading = false
                        }
                    } catch {
                        await MainActor.run {
                            self.errorMessage = "Failed to load video: \(error.localizedDescription)"
                            self.isLoading = false
                        }
                    }
                }
            }
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
} 