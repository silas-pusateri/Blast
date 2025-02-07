import SwiftUI
import AVKit
import FirebaseFirestore
import FirebaseStorage

// Video preloading manager
class VideoPreloadManager {
    static let shared = VideoPreloadManager()
    private var preloadedPlayers: [String: AVPlayer] = [:]
    private let preloadQueue = DispatchQueue(label: "com.blast.videopreload")
    
    private init() {}
    
    func preloadVideo(video: Video) {
        // Clear any existing preloaded player for this video ID first
        clearPreloadedPlayer(for: video.id)
        
        guard let videoURL = URL(string: video.url) else { return }
        
        preloadQueue.async { [weak self] in
            let asset = AVAsset(url: videoURL)
            let playerItem = AVPlayerItem(asset: asset)
            
            DispatchQueue.main.async {
                self?.preloadedPlayers[video.id] = AVPlayer(playerItem: playerItem)
            }
        }
    }
    
    func getPreloadedPlayer(for videoId: String) -> AVPlayer? {
        return preloadedPlayers[videoId]
    }
    
    func clearPreloadedPlayer(for videoId: String) {
        if let player = preloadedPlayers[videoId] {
            player.pause()
            player.replaceCurrentItem(with: nil)
            preloadedPlayers.removeValue(forKey: videoId)
        }
    }
    
    func clearAllPreloadedVideos() {
        for (videoId, player) in preloadedPlayers {
            player.pause()
            player.replaceCurrentItem(with: nil)
            preloadedPlayers.removeValue(forKey: videoId)
        }
    }
    
    func preloadNextVideo(currentVideo: Video, videos: [Video]) {
        guard let currentIndex = videos.firstIndex(where: { $0.id == currentVideo.id }),
              currentIndex + 1 < videos.count else { return }
        
        let nextVideo = videos[currentIndex + 1]
        preloadVideo(video: nextVideo)
    }
}

struct VideoView: View {
    let video: Video
    @EnvironmentObject private var videoViewModel: VideoViewModel
    @State private var isShowingComments = false
    @State private var isLiked = false
    @State private var likes: Int
    @State private var player: AVPlayer?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isPlaying = true
    @State private var isVisible = false
    @State private var playerTimeObserver: Any?

    init(video: Video) {
        self.video = video
        self._likes = State(initialValue: video.likes)
    }
    
    private func loadVideo() {
        // Clear any existing player and observers
        cleanup()
        
        // First check if we have a preloaded video
        if let preloadedPlayer = VideoPreloadManager.shared.getPreloadedPlayer(for: video.id) {
            setupPlayer(preloadedPlayer)
            
            // Preload next video
            VideoPreloadManager.shared.preloadNextVideo(currentVideo: video, videos: videoViewModel.videos)
            return
        }
        
        // If no preloaded video, load normally
        guard let videoURL = URL(string: video.url) else {
            errorMessage = "Invalid video URL"
            isLoading = false
            return
        }
        
        // Create and setup player
        setupPlayer(AVPlayer(url: videoURL))
    }
    
    private func cleanup() {
        if let oldObserver = playerTimeObserver {
            player?.removeTimeObserver(oldObserver)
            playerTimeObserver = nil
        }
        
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        
        NotificationCenter.default.removeObserver(
            self,
            name: .AVPlayerItemDidPlayToEndTime,
            object: nil
        )
    }
    
    private func setupPlayer(_ newPlayer: AVPlayer) {
        cleanup()
        
        self.player = newPlayer
        newPlayer.isMuted = !isVisible
        
        // Add periodic time observer for more precise synchronization
        let interval = CMTime(seconds: 0.01, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        playerTimeObserver = newPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [newPlayer] _ in
            guard let currentItem = newPlayer.currentItem else { return }
            
            if #available(iOS 16.0, *) {
                Task {
                    let videoTracks = try? await currentItem.asset.loadTracks(withMediaType: .video)
                    let audioTracks = try? await currentItem.asset.loadTracks(withMediaType: .audio)
                    
                    if let videoTrack = videoTracks?.first,
                       let audioTrack = audioTracks?.first {
                        // Load timeRanges
                        let videoTimeRange = try? await videoTrack.load(.timeRange)
                        let audioTimeRange = try? await audioTrack.load(.timeRange)
                        
                        if let videoStart = videoTimeRange?.start.seconds,
                           let audioStart = audioTimeRange?.start.seconds,
                           abs(videoStart - audioStart) > 0.1 {
                            // Reset playback to fix sync
                            await MainActor.run {
                                let currentTime = newPlayer.currentTime()
                                newPlayer.seek(to: currentTime, toleranceBefore: .zero, toleranceAfter: .zero)
                            }
                        }
                    }
                }
            } else {
                // Fallback for iOS 15 and earlier
                let videoTracks = currentItem.asset.tracks(withMediaType: .video)
                let audioTracks = currentItem.asset.tracks(withMediaType: .audio)
                
                if let videoTrack = videoTracks.first,
                   let audioTrack = audioTracks.first,
                   abs(videoTrack.timeRange.start.seconds - audioTrack.timeRange.start.seconds) > 0.1 {
                    // Reset playback to fix sync
                    let currentTime = newPlayer.currentTime()
                    newPlayer.seek(to: currentTime, toleranceBefore: .zero, toleranceAfter: .zero)
                }
            }
        }
        
        isLoading = false
    }
    
    var body: some View {
        ZStack {
            Color.black
            
            if isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
            } else if let error = errorMessage {
                VStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.white)
                    Text(error)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding()
                }
            } else if let player = player {
                ZStack {
                    AVPlayerControllerRepresented(player: player)
                        .disabled(true)
                        .onAppear {
                            // Start playing when view appears
                            player.seek(to: .zero)
                            // Set initial mute state based on visibility
                            player.isMuted = !isVisible
                            if isPlaying {
                                player.play()
                            }
                            
                            // Setup video looping
                            NotificationCenter.default.addObserver(
                                forName: .AVPlayerItemDidPlayToEndTime,
                                object: player.currentItem,
                                queue: .main) { _ in
                                    player.seek(to: .zero)
                                    if isPlaying {
                                        player.play()
                                    }
                                }
                        }
                        .onDisappear {
                            cleanup()
                            // Clear preloaded video when view disappears
                            VideoPreloadManager.shared.clearPreloadedPlayer(for: video.id)
                        }
                    
                    // Pause indicator overlay
                    if !isPlaying {
                        Circle()
                            .fill(Color.black.opacity(0.5))
                            .frame(width: 80, height: 80)
                            .overlay(
                                Image(systemName: "play.fill")
                                    .font(.system(size: 30))
                                    .foregroundColor(.white)
                            )
                    }
                }
                .contentShape(Rectangle())  // Make the entire area tappable
                .onTapGesture {
                    isPlaying.toggle()
                    if isPlaying {
                        player.play()
                        player.isMuted = !isVisible
                    } else {
                        player.pause()
                    }
                }
                
                // Video overlay content
                VStack {
                    Spacer()
                    
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(video.userId)
                                .font(.system(size: 16, weight: .semibold))
                            Text(video.caption)
                                .font(.system(size: 14, weight: .regular))
                                .lineLimit(2)
                        }
                        .foregroundColor(.white)
                        
                        Spacer()
                        
                        VStack(spacing: 20) {
                            Button(action: {
                                isLiked.toggle()
                                likes += isLiked ? 1 : -1
                                // Update likes in Firestore
                                let db = Firestore.firestore()
                                db.collection("videos").document(video.id)
                                    .updateData(["likes": likes])
                            }) {
                                VStack(spacing: 4) {
                                    Image(systemName: isLiked ? "heart.fill" : "heart")
                                        .foregroundColor(isLiked ? .red : .white)
                                        .font(.system(size: 26))
                                    Text("\(likes)")
                                        .foregroundColor(.white)
                                        .font(.system(size: 12))
                                }
                            }
                            
                            Button(action: {
                                isShowingComments = true
                            }) {
                                VStack(spacing: 4) {
                                    Image(systemName: "bubble.right")
                                        .foregroundColor(.white)
                                        .font(.system(size: 26))
                                    Text("\(video.comments)")
                                        .foregroundColor(.white)
                                        .font(.system(size: 12))
                                }
                            }
                            
                            Button(action: {
                                // Share action
                                let activityViewController = UIActivityViewController(
                                    activityItems: [URL(string: video.url)!],
                                    applicationActivities: nil
                                )
                                
                                // Present the share sheet
                                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                                   let window = windowScene.windows.first,
                                   let rootViewController = window.rootViewController {
                                    rootViewController.present(activityViewController, animated: true)
                                }
                            }) {
                                VStack(spacing: 4) {
                                    Image(systemName: "arrowshape.turn.up.right")
                                        .foregroundColor(.white)
                                        .font(.system(size: 26))
                                    Text("Share")
                                        .foregroundColor(.white)
                                        .font(.system(size: 12))
                                }
                            }
                        }
                        .padding(.bottom, 20)
                    }
                    .padding()
                }
            }
        }
        .sheet(isPresented: $isShowingComments) {
            CommentView(video: video)
        }
        .onAppear {
            loadVideo()
        }
        .onDisappear {
            cleanup()
            // Clear preloaded video when view disappears
            VideoPreloadManager.shared.clearPreloadedPlayer(for: video.id)
        }
        // Add visibility detection using GeometryReader
        .overlay(
            GeometryReader { proxy -> Color in
                let isCurrentlyVisible = proxy.frame(in: .global).intersects(UIScreen.main.bounds)
                if self.isVisible != isCurrentlyVisible {
                    // Use DispatchQueue to avoid SwiftUI state update warning
                    DispatchQueue.main.async {
                        self.isVisible = isCurrentlyVisible
                        self.player?.isMuted = !isCurrentlyVisible
                        
                        if isCurrentlyVisible && self.isPlaying {
                            self.player?.play()
                        } else if !isCurrentlyVisible {
                            self.player?.pause()
                        }
                    }
                }
                return Color.clear
            }
        )
    }
}

struct AVPlayerControllerRepresented: UIViewControllerRepresentable {
    let player: AVPlayer
    
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspectFill
        return controller
    }
    
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {}
}

struct VideoView_Previews: PreviewProvider {
    static var previews: some View {
        VideoView(video: Video(
            id: "1",
            url: "https://example.com/video1.mp4",
            caption: "A beautiful sunset",
            userId: "user1",
            likes: 100,
            comments: 50
        ))
        .environmentObject(AuthenticationState())
    }
}

// Add visibility preference key
private struct VisibilityPreferenceKey: PreferenceKey {
    static var defaultValue: Bool = false
    
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = nextValue()
    }
} 
