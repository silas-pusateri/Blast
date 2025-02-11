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
                    print("❌ [VideoPreloadManager] Failed to load asset for video \(video.id): \(error)")
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
    @State private var currentVideoURL: String?
    @StateObject private var playerController = VideoPlayerController()
    @State private var isRefreshingURL = false

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
        print("📹 [VideoView] Starting loadVideo for videoId: \(video.id), URL: \(video.url)")
        
        // If the URL hasn't changed and we're not refreshing, don't reload
        if currentVideoURL == video.url && !isRefreshingURL {
            print("📹 [VideoView] Skipping reload - URL hasn't changed")
            return
        }
        currentVideoURL = video.url
        isRefreshingURL = false
        
        // First check if we have a preloaded video
        if let preloadedPlayer = VideoPreloadManager.shared.getPreloadedPlayer(for: video.id) {
            print("📹 [VideoView] Using preloaded player for videoId: \(video.id)")
            playerController.player = preloadedPlayer
            playerController.isLoading = false
            
            // Preload next video
            VideoPreloadManager.shared.preloadNextVideo(currentVideo: video, videos: videoViewModel.videos)
            return
        }
        
        // If no preloaded video, load normally
        guard let videoURL = URL(string: video.url) else {
            print("❌ [VideoView] Failed to create URL from string: \(video.url)")
            playerController.errorMessage = "Invalid video URL"
            playerController.isLoading = false
            return
        }
        
        print("📹 [VideoView] Creating new player for URL: \(videoURL)")
        // Set up error handler for URL refresh
        playerController.onLoadError = {
            await refreshVideoURL()
        }
        // Create and setup player
        playerController.setupPlayer(videoURL)
    }
    
    private func refreshVideoURL() async {
        print("🔄 [VideoView] Refreshing video URL for videoId: \(video.id)")
        playerController.isLoading = true
        playerController.errorMessage = nil
        
        do {
            // Extract the path from the current URL
            guard let currentURL = URL(string: video.url),
                  let storagePath = currentURL.path.components(separatedBy: "o/").last?.removingPercentEncoding else {
                throw NSError(domain: "VideoView", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid video URL format"])
            }
            
            // Get a fresh download URL
            let storage = Storage.storage()
            let storageRef = storage.reference().child(storagePath)
            let newURL = try await storageRef.downloadURL()
            
            // Update the video URL in Firestore
            let db = Firestore.firestore()
            try await db.collection("videos").document(video.id).updateData([
                "videoUrl": newURL.absoluteString
            ])
            
            // Update the local video model
            await MainActor.run {
                currentVideoURL = nil // Reset so loadVideo will work
                if let index = videoViewModel.videos.firstIndex(where: { $0.id == video.id }) {
                    videoViewModel.videos[index] = Video(
                        id: video.id,
                        url: newURL.absoluteString,
                        caption: video.caption,
                        userId: video.userId,
                        likes: video.likes,
                        comments: video.comments,
                        previousVersionId: video.previousVersionId,
                        changeDescription: video.changeDescription
                    )
                }
                loadVideo()
            }
        } catch {
            print("❌ [VideoView] Failed to refresh video URL: \(error)")
            await MainActor.run {
                playerController.errorMessage = "Failed to refresh video: \(error.localizedDescription)"
                playerController.isLoading = false
            }
        }
    }
    
    var body: some View {
        ZStack {
            Color.black
            
            if playerController.isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
            } else if let error = playerController.errorMessage {
                VStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.white)
                    Text(error)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding()
                }
            } else if let player = playerController.player {
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
                            player.pause()
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
        .onChange(of: video.url) { oldValue, newValue in
            if oldValue != newValue {
                loadVideo()
            }
        }
        .onAppear {
            loadVideo()
            fetchUsername()
        }
        .onDisappear {
            playerController.player?.pause()
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
                                playerController.player?.isMuted = !isCurrentlyVisible
                                
                                if isCurrentlyVisible && self.isPlaying {
                                    playerController.player?.play()
                                } else if !isCurrentlyVisible {
                                    playerController.player?.pause()
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
        print("🎬 [AVPlayerControllerRepresented] Creating AVPlayerViewController")
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspectFill
        
        // Log player status
        if let player = player {
            print("🎬 [AVPlayerControllerRepresented] Player rate: \(player.rate)")
            if let currentItem = player.currentItem {
                print("🎬 [AVPlayerControllerRepresented] Player item status: \(currentItem.status.rawValue)")
            } else {
                print("❌ [AVPlayerControllerRepresented] No current item")
            }
        } else {
            print("❌ [AVPlayerControllerRepresented] Player is nil")
        }
        
        return controller
    }
    
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        print("🔄 [AVPlayerControllerRepresented] Updating AVPlayerViewController")
        if uiViewController.player !== player {
            uiViewController.player = player
            // Log player status after update
            if let player = player {
                print("🔄 [AVPlayerControllerRepresented] Updated player rate: \(player.rate)")
                if let currentItem = player.currentItem {
                    print("🔄 [AVPlayerControllerRepresented] Updated player item status: \(currentItem.status.rawValue)")
                }
            }
        }
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
            comments: 50,
            previousVersionId: nil,
            changeDescription: nil
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

// Add VideoPlayerController class to handle player lifecycle
class VideoPlayerController: NSObject, ObservableObject {
    @Published var player: AVPlayer?
    @Published var isLoading = true
    @Published var errorMessage: String?
    var playerTimeObserver: Any?
    var onLoadError: (() async -> Void)?
    
    func setupPlayer(_ videoURL: URL) {
        print("🎮 [VideoPlayerController] Setting up player for URL: \(videoURL)")
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
                print("🎮 [VideoPlayerController] Loading asset...")
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
                    print("🎮 [VideoPlayerController] Asset loaded successfully")
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
                    
                    print("🎮 [VideoPlayerController] Player setup complete")
                    self.isLoading = false
                }
            } catch {
                print("❌ [VideoPlayerController] Failed to load asset: \(error)")
                await MainActor.run {
                    self.errorMessage = "Failed to load video: \(error.localizedDescription)"
                    self.isLoading = false
                }
                // Try to refresh the URL
                if let onLoadError = onLoadError {
                    await onLoadError()
                }
            }
        }
    }
    
    @objc private func playerItemFailedToPlay(_ notification: Notification) {
        if let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error {
            print("❌ [VideoPlayerController] Failed to play to end: \(error)")
            errorMessage = "Failed to play video: \(error.localizedDescription)"
            // Try to refresh the URL
            if let onLoadError = onLoadError {
                Task {
                    await onLoadError()
                }
            }
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
            
            // Handle player item status change
            print("🎮 [VideoPlayerController] Player item status changed to: \(status.rawValue)")
            switch status {
            case .readyToPlay:
                print("✅ [VideoPlayerController] Player ready to play")
                player?.play()
            case .failed:
                if let error = player?.currentItem?.error {
                    print("❌ [VideoPlayerController] Player failed with error: \(error)")
                    errorMessage = "Failed to load video"
                    // Try to refresh the URL
                    if let onLoadError = onLoadError {
                        Task {
                            await onLoadError()
                        }
                    }
                }
            case .unknown:
                print("⚠️ [VideoPlayerController] Player status unknown")
                break
            @unknown default:
                print("⚠️ [VideoPlayerController] Player status: unknown default case")
                break
            }
        }
    }
    
    func cleanup() {
        print("🧹 [VideoPlayerController] Starting cleanup")
        if let oldObserver = playerTimeObserver {
            print("🧹 [VideoPlayerController] Removing time observer")
            player?.removeTimeObserver(oldObserver)
            playerTimeObserver = nil
        }
        
        // Remove KVO observer if needed
        if let currentItem = player?.currentItem {
            print("🧹 [VideoPlayerController] Removing KVO observer")
            currentItem.removeObserver(self, forKeyPath: #keyPath(AVPlayerItem.status))
        }
        
        print("🧹 [VideoPlayerController] Pausing and nullifying player")
        player?.pause()
        player = nil
    }
    
    deinit {
        print("👋 [VideoPlayerController] Deinitializing")
        cleanup()
    }
} 
