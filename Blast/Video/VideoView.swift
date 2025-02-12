import SwiftUI
import AVKit
import FirebaseFirestore
import FirebaseStorage
import FirebaseAuth

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
            
            // Create asset with options for better loading
            let assetOptions = [
                AVURLAssetPreferPreciseDurationAndTimingKey: true
            ]
            let asset = AVURLAsset(url: videoURL, options: assetOptions)
            
            // Load the asset asynchronously
            Task {
                do {
                    // Load duration and tracks to ensure asset is playable
                    _ = try await asset.load(.duration)
                    _ = try await asset.load(.tracks)
                    
                    let playerItem = AVPlayerItem(asset: asset)
                    
                    await MainActor.run {
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
                } catch {
                    print("❌ Failed to load asset for video \(video.id): \(error)")
                }
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
    let videoViewModel: VideoViewModel
    @State private var isShowingComments = false
    @State private var isLiked = false
    @State private var likes: Int
    @State private var player: AVPlayer?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isPlaying = false
    @State private var isVisible = false
    @State private var playerTimeObserver: Any?
    @State private var username: String = ""
    @State private var currentVideoURL: String?
    @StateObject private var playerController = VideoPlayerController()
    @State private var isShowingChanges = false

    init(video: Video, videoViewModel: VideoViewModel) {
        self.video = video
        self.videoViewModel = videoViewModel
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
        // If the URL hasn't changed, don't reload
        if currentVideoURL == video.url {
            return
        }
        currentVideoURL = video.url
        
        // First check if we have a preloaded video
        if let preloadedPlayer = VideoPreloadManager.shared.getPreloadedPlayer(for: video.id) {
            playerController.player = preloadedPlayer
            playerController.isLoading = false
            // Ensure video starts paused
            preloadedPlayer.pause()
            
            // Preload next video
            VideoPreloadManager.shared.preloadNextVideo(currentVideo: video, videos: videoViewModel.videos)
            return
        }
        
        // If no preloaded video, load normally
        guard let videoURL = URL(string: video.url) else {
            playerController.errorMessage = "Invalid video URL"
            playerController.isLoading = false
            return
        }
        
        // Check if this is a local file URL
        if videoURL.isFileURL {
            // Check if file exists
            let fileManager = FileManager.default
            guard fileManager.fileExists(atPath: videoURL.path) else {
                playerController.errorMessage = "Video file not found"
                playerController.isLoading = false
                return
            }
            
            // Check if file is readable
            guard fileManager.isReadableFile(atPath: videoURL.path) else {
                playerController.errorMessage = "Video file is not accessible"
                playerController.isLoading = false
                return
            }
        }
        
        // Create and setup player
        playerController.setupPlayer(videoURL)
    }
    
    private func handleVisibilityChanged() {
        if isVisible {
            if !isPlaying {
                playerController.player?.play()
                isPlaying = true
            }
            playerController.player?.isMuted = false
        } else {
            playerController.player?.isMuted = true
            playerController.player?.pause()
            isPlaying = false
        }
    }
    
    var body: some View {
        ZStack {
            Color.black
            
            if playerController.isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
            } else if let errorMessage = playerController.errorMessage {
                VStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundColor(.yellow)
                    Text(errorMessage)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding()
                }
            } else if let player = playerController.player {
                ZStack {
                    CustomVideoPlayer(player: player)
                        .onAppear {
                            isVisible = true
                            handleVisibilityChanged()
                            
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
                            isVisible = false
                            handleVisibilityChanged()
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
                    } else {
                        player.pause()
                    }
                }
                
                // Video overlay content
                VStack {
                    Spacer()
                    
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(username)
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            Text(video.caption)
                                .font(.subheadline)
                                .foregroundColor(.white)
                        }
                        
                        Spacer()
                        
                        VStack(spacing: 20) {
                            Button(action: toggleLike) {
                                VStack {
                                    Image(systemName: isLiked ? "heart.fill" : "heart")
                                        .foregroundColor(isLiked ? .red : .white)
                                        .font(.system(size: 28))
                                    
                                    Text("\(likes)")
                                        .font(.caption)
                                        .foregroundColor(.white)
                                }
                            }
                            
                            Button(action: { isShowingComments = true }) {
                                VStack {
                                    Image(systemName: "bubble.right")
                                        .font(.system(size: 28))
                                        .foregroundColor(.white)
                                    
                                    Text("\(video.comments)")
                                        .font(.caption)
                                        .foregroundColor(.white)
                                }
                            }
                            
                            Button(action: { isShowingChanges = true }) {
                                VStack {
                                    Image(systemName: "pencil.circle")
                                        .font(.system(size: 28))
                                        .foregroundColor(.white)
                                    
                                    Text("Changes")
                                        .font(.caption)
                                        .foregroundColor(.white)
                                }
                            }
                        }
                        .padding(.trailing)
                    }
                    .padding(.bottom, 48)
                    .padding(.horizontal)
                }
            }
        }
        .onAppear {
            loadVideo()
            fetchUsername()
        }
        .onChange(of: isVisible) { newValue in
            handleVisibilityChanged()
        }
        .sheet(isPresented: $isShowingComments) {
            NavigationView {
                CommentView(video: video)
            }
        }
        .sheet(isPresented: $isShowingChanges) {
            if video.userId == Auth.auth().currentUser?.uid {
                ChangesReviewView(video: video, videoViewModel: videoViewModel)
            } else {
                SuggestChangesView(video: video, videoViewModel: videoViewModel)
            }
        }
    }
    
    private func toggleLike() {
        isLiked.toggle()
        likes += isLiked ? 1 : -1
        // Update likes in Firestore
        let db = Firestore.firestore()
        db.collection("videos").document(video.id)
            .updateData(["likes": likes])
    }
}

// Add CustomVideoPlayer to ensure proper video behavior
struct CustomVideoPlayer: UIViewControllerRepresentable {
    let player: AVPlayer
    
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
        if uiViewController.player !== player {
            uiViewController.player = player
        }
    }
}

struct VideoView_Previews: PreviewProvider {
    static var previews: some View {
        VideoView(
            video: Video(
                id: "1",
                url: "https://example.com/video1.mp4",
                caption: "A beautiful sunset",
                userId: "user1",
                likes: 100,
                comments: 50
            ),
            videoViewModel: VideoViewModel()
        )
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

// Add VideoPlayerController class to handle player lifecycle
class VideoPlayerController: NSObject, ObservableObject {
    @Published var player: AVPlayer?
    @Published var isLoading = true
    @Published var errorMessage: String?
    var playerTimeObserver: Any?
    
    func setupPlayer(_ videoURL: URL) {
        cleanup()
        
        // Create an asset options dictionary for better loading behavior
        let assetOptions = [
            AVURLAssetPreferPreciseDurationAndTimingKey: true
        ]
        
        // Create the asset with options
        let asset = AVURLAsset(url: videoURL, options: assetOptions)
        
        // Load the asset asynchronously
        Task {
            do {
                // Load duration and tracks to ensure asset is playable
                _ = try await asset.load(.duration)
                let tracks = try await asset.load(.tracks)
                
                // Verify we have video tracks
                guard tracks.contains(where: { $0.mediaType == .video }) else {
                    await MainActor.run {
                        self.errorMessage = "Invalid video file format"
                        self.isLoading = false
                    }
                    return
                }
                
                await MainActor.run {
                    let playerItem = AVPlayerItem(asset: asset)
                    let newPlayer = AVPlayer(playerItem: playerItem)
                    self.player = newPlayer
                    
                    // Add error observer for player item
                    NotificationCenter.default.addObserver(
                        self,
                        selector: #selector(self.playerItemFailedToPlay(_:)),
                        name: NSNotification.Name.AVPlayerItemFailedToPlayToEndTime,
                        object: playerItem
                    )
                    
                    // Add KVO observer for player item status
                    playerItem.addObserver(self, forKeyPath: #keyPath(AVPlayerItem.status), options: [.old, .new], context: nil)
                    
                    self.isLoading = false
                }
            } catch {
                print("Failed to load video: \(error.localizedDescription)")
                await MainActor.run {
                    self.errorMessage = "Failed to load video: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }
    
    @objc private func playerItemFailedToPlay(_ notification: Notification) {
        if let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error {
            errorMessage = "Failed to play video: \(error.localizedDescription)"
        }
    }
    
    override public func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == #keyPath(AVPlayerItem.status) {
            let status: AVPlayerItem.Status
            if let statusNumber = change?[.newKey] as? NSNumber {
                status = AVPlayerItem.Status(rawValue: statusNumber.intValue)!
            } else {
                status = .unknown
            }
            
            switch status {
            case .readyToPlay:
                player?.play()
            case .failed:
                if let error = player?.currentItem?.error {
                    errorMessage = "Failed to load video"
                }
            case .unknown:
                break
            @unknown default:
                break
            }
        }
    }
    
    func cleanup() {
        if let oldObserver = playerTimeObserver {
            player?.removeTimeObserver(oldObserver)
            playerTimeObserver = nil
        }
        
        // Remove KVO observer if needed
        if let currentItem = player?.currentItem {
            currentItem.removeObserver(self, forKeyPath: #keyPath(AVPlayerItem.status))
        }
        
        player?.pause()
        player = nil
    }
    
    deinit {
        cleanup()
    }
} 
