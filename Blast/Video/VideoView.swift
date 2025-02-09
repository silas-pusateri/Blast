import SwiftUI
import AVKit
import FirebaseFirestore
import FirebaseStorage

// Video preloading manager
class VideoPreloadManager {
    static let shared = VideoPreloadManager()
    private var preloadedPlayers: [String: AVPlayer] = [:]
    private let preloadQueue = DispatchQueue(label: "com.blast.videopreload")
    private let maxCachedVideos = 4 // Keep at most 3 videos in cache
    private var recentVideoIds: [String] = [] // Track order of videos for LRU cache
    
    private init() {}
    
    func preloadVideo(video: Video) {
        preloadQueue.async { [weak self] in
            guard let self = self else { return }
            
            // If video is already preloaded, move it to most recent
            if self.preloadedPlayers[video.id] != nil {
                self.updateRecentVideo(video.id)
                return
            }
            
            guard let videoURL = URL(string: video.url) else { return }
            
            let asset = AVAsset(url: videoURL)
            let playerItem = AVPlayerItem(asset: asset)
            
            DispatchQueue.main.async {
                // Remove oldest video if we're at capacity
                if self.recentVideoIds.count >= self.maxCachedVideos {
                    if let oldestVideoId = self.recentVideoIds.first {
                        self.clearPreloadedPlayer(for: oldestVideoId)
                        self.recentVideoIds.removeFirst()
                    }
                }
                
                // Add new video
                self.preloadedPlayers[video.id] = AVPlayer(playerItem: playerItem)
                self.updateRecentVideo(video.id)
            }
        }
    }
    
    private func updateRecentVideo(_ videoId: String) {
        recentVideoIds.removeAll { $0 == videoId }
        recentVideoIds.append(videoId)
    }
    
    func getPreloadedPlayer(for videoId: String) -> AVPlayer? {
        if let player = preloadedPlayers[videoId] {
            updateRecentVideo(videoId)
            return player
        }
        return nil
    }
    
    func clearPreloadedPlayer(for videoId: String) {
        if let player = preloadedPlayers[videoId] {
            player.pause()
            player.replaceCurrentItem(with: nil)
            preloadedPlayers.removeValue(forKey: videoId)
            recentVideoIds.removeAll { $0 == videoId }
        }
    }
    
    func clearAllPreloadedVideos() {
        for (videoId, player) in preloadedPlayers {
            player.pause()
            player.replaceCurrentItem(with: nil)
            preloadedPlayers.removeValue(forKey: videoId)
        }
        recentVideoIds.removeAll()
    }
    
    func preloadNextVideo(currentVideo: Video, videos: [Video]) {
        guard let currentIndex = videos.firstIndex(where: { $0.id == currentVideo.id }) else { return }
        
        // Preload next video if available
        if currentIndex + 1 < videos.count {
            let nextVideo = videos[currentIndex + 1]
            preloadVideo(video: nextVideo)
        }
        
        // Preload previous video if available and not already cached
        if currentIndex > 0 {
            let previousVideo = videos[currentIndex - 1]
            if preloadedPlayers[previousVideo.id] == nil {
                preloadVideo(video: previousVideo)
            }
        }
    }
}

// Add username caching class
class UsernameCache {
    static let shared = UsernameCache()
    private var cache: [String: String] = [:]
    private let queue = DispatchQueue(label: "com.blast.usernamecache")
    
    private init() {}
    
    func getUsername(for userId: String) -> String? {
        queue.sync {
            return cache[userId]
        }
    }
    
    func setUsername(_ username: String, for userId: String) {
        queue.async {
            self.cache[userId] = username
        }
    }
    
    func clearCache() {
        queue.async {
            self.cache.removeAll()
        }
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
    @State private var username: String = ""

    init(video: Video) {
        self.video = video
        self._likes = State(initialValue: video.likes)
    }
    
    // Add username fetching function
    private func fetchUsername() {
        // Check cache first
        if let cachedUsername = UsernameCache.shared.getUsername(for: video.userId) {
            username = cachedUsername
            return
        }
        
        // If not in cache, fetch from Firestore
        let db = Firestore.firestore()
        db.collection("users").document(video.userId).getDocument { snapshot, error in
            guard let data = snapshot?.data(),
                  let fetchedUsername = data["username"] as? String else {
                username = "User"
                return
            }
            
            // Update cache and state
            UsernameCache.shared.setUsername(fetchedUsername, for: video.userId)
            username = fetchedUsername
        }
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
                            // Only pause the player when view disappears, don't clear it
                            player.pause()
                            
                            if let oldObserver = playerTimeObserver {
                                player.removeTimeObserver(oldObserver)
                                playerTimeObserver = nil
                            }
                            
                            NotificationCenter.default.removeObserver(
                                self,
                                name: .AVPlayerItemDidPlayToEndTime,
                                object: nil
                            )
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
                            Text("@\(username)")
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
            fetchUsername()
        }
        .onDisappear {
            // Only pause the player when view disappears, don't clear it
            player?.pause()
            
            if let oldObserver = playerTimeObserver {
                player?.removeTimeObserver(oldObserver)
                playerTimeObserver = nil
            }
            
            NotificationCenter.default.removeObserver(
                self,
                name: .AVPlayerItemDidPlayToEndTime,
                object: nil
            )
        }
        // Add visibility detection using GeometryReader
        .overlay(
            GeometryReader { proxy in
                Color.clear
                    .preference(
                        key: VisibilityPreferenceKey.self,
                        value: proxy.frame(in: .global).intersects(UIScreen.main.bounds)
                    )
                    .onPreferenceChange(VisibilityPreferenceKey.self) { isCurrentlyVisible in
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
                    }
            }
        )
    }
}

struct AVPlayerControllerRepresented: UIViewControllerRepresentable {
    let player: AVPlayer?
    
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspectFill
        return controller
    }
    
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        uiViewController.player = player
    }
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
