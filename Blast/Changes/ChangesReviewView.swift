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
        .sheet(isPresented: $showingPreview) {
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
    
    var body: some View {
        NavigationView {
            Group {
                if let editUrl = change.editUrl,
                   let url = URL(string: editUrl) {
                    VideoPlayer(player: AVPlayer(url: url))
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
                        dismiss()
                    }
                }
            }
        }
    }
} 