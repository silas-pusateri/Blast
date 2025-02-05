import SwiftUI
import AVKit
import FirebaseFirestore
import FirebaseStorage

// Video preloading manager
class VideoPreloadManager {
    static let shared = VideoPreloadManager()
    private var preloadedPlayers: [Int: AVPlayer] = [:]
    private var preloadedData: [Int: VideoData] = [:]
    private let preloadQueue = DispatchQueue(label: "com.blast.videopreload")
    
    private init() {}
    
    func preloadVideo(at index: Int) {
        guard preloadedPlayers[index] == nil else { return }
        
        let db = Firestore.firestore()
        db.collection("videos")
            .order(by: "timestamp", descending: true)
            .limit(to: index + 1)
            .getDocuments { [weak self] snapshot, error in
                guard let self = self,
                      error == nil,
                      let documents = snapshot?.documents,
                      index < documents.count else { return }
                
                let document = documents[index]
                let decoder = Firestore.Decoder()
                decoder.userInfo[.documentPath] = document.reference.path
                
                do {
                    let data = try document.data(as: VideoData.self, decoder: decoder)
                    guard let videoURL = URL(string: data.videoUrl) else { return }
                    
                    preloadQueue.async {
                        let asset = AVAsset(url: videoURL)
                        let playerItem = AVPlayerItem(asset: asset)
                        
                        DispatchQueue.main.async {
                            self.preloadedPlayers[index] = AVPlayer(playerItem: playerItem)
                            self.preloadedData[index] = data
                        }
                    }
                } catch {
                    print("Error preloading video: \(error)")
                }
            }
    }
    
    func getPreloadedPlayer(for index: Int) -> (AVPlayer, VideoData)? {
        guard let player = preloadedPlayers[index],
              let data = preloadedData[index] else { return nil }
        return (player, data)
    }
    
    func clearPreloadedPlayer(for index: Int) {
        preloadedPlayers[index]?.pause()
        preloadedPlayers.removeValue(forKey: index)
        preloadedData.removeValue(forKey: index)
    }
    
    func clearAllPreloadedVideos() {
        for (_, player) in preloadedPlayers {
            player.pause()
        }
        preloadedPlayers.removeAll()
        preloadedData.removeAll()
    }
    
    func preloadNextVideo(currentIndex: Int) {
        preloadVideo(at: currentIndex + 2)
    }
}

struct VideoView: View {
    let index: Int
    @State private var isShowingComments = false
    @State private var isLiked = false
    @State private var likes = 0
    @State private var videoData: VideoData?
    @State private var player: AVPlayer?
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    init(index: Int) {
        self.index = index
    }
    
    private func loadVideo() {
        // First check if we have a preloaded video
        if let (preloadedPlayer, preloadedData) = VideoPreloadManager.shared.getPreloadedPlayer(for: index) {
            self.player = preloadedPlayer
            self.videoData = preloadedData
            self.likes = preloadedData.likes
            self.isLoading = false
            
            // Preload next video
            VideoPreloadManager.shared.preloadNextVideo(currentIndex: index)
            return
        }
        
        // If no preloaded video, load normally
        let db = Firestore.firestore()
        db.collection("videos")
            .order(by: "timestamp", descending: true)
            .limit(to: index + 1)
            .getDocuments { snapshot, error in
                if let error = error {
                    DispatchQueue.main.async {
                        errorMessage = "Error loading video: \(error.localizedDescription)"
                        isLoading = false
                    }
                    return
                }
                
                guard let documents = snapshot?.documents,
                      index < documents.count else {
                    DispatchQueue.main.async {
                        errorMessage = "No video found"
                        isLoading = false
                    }
                    return
                }
                
                let document = documents[index]
                let decoder = Firestore.Decoder()
                decoder.userInfo[.documentPath] = document.reference.path
                
                do {
                    let data = try document.data(as: VideoData.self, decoder: decoder)
                    guard let videoURL = URL(string: data.videoUrl) else {
                        DispatchQueue.main.async {
                            errorMessage = "Invalid video URL"
                            isLoading = false
                        }
                        return
                    }
                    
                    DispatchQueue.main.async {
                        self.videoData = data
                        self.likes = data.likes
                        self.player = AVPlayer(url: videoURL)
                        self.isLoading = false
                        
                        // Preload next video
                        VideoPreloadManager.shared.preloadNextVideo(currentIndex: index)
                    }
                } catch {
                    DispatchQueue.main.async {
                        errorMessage = "Error decoding video data: \(error.localizedDescription)"
                        isLoading = false
                    }
                }
            }
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
                AVPlayerControllerRepresented(player: player)
                    .disabled(true)
                    .onAppear {
                        // Start playing when view appears
                        player.seek(to: .zero)
                        player.play()
                        
                        // Setup video looping
                        NotificationCenter.default.addObserver(
                            forName: .AVPlayerItemDidPlayToEndTime,
                            object: player.currentItem,
                            queue: .main) { _ in
                                player.seek(to: .zero)
                                player.play()
                            }
                    }
                    .onDisappear {
                        // Cleanup when view disappears
                        player.pause()
                        NotificationCenter.default.removeObserver(
                            self,
                            name: .AVPlayerItemDidPlayToEndTime,
                            object: player.currentItem
                        )
                        // Clear preloaded video for this index when view disappears
                        VideoPreloadManager.shared.clearPreloadedPlayer(for: index)
                    }
                
                // Video overlay content
                VStack {
                    Spacer()
                    
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(videoData?.userId ?? "unknown")
                                .font(.system(size: 16, weight: .semibold))
                            Text(videoData?.caption ?? "")
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
                                if let videoData = videoData {
                                    let db = Firestore.firestore()
                                    db.collection("videos").document(videoData.id)
                                        .updateData(["likes": likes])
                                }
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
                                    Text("\(videoData?.comments ?? 0)")
                                        .foregroundColor(.white)
                                        .font(.system(size: 12))
                                }
                            }
                            
                            Button(action: {
                                // Share action
                                if let videoUrl = videoData?.videoUrl {
                                    let activityViewController = UIActivityViewController(
                                        activityItems: [URL(string: videoUrl)!],
                                        applicationActivities: nil
                                    )
                                    
                                    // Present the share sheet
                                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                                       let window = windowScene.windows.first,
                                       let rootViewController = window.rootViewController {
                                        rootViewController.present(activityViewController, animated: true)
                                    }
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
            CommentView(commentCount: videoData?.comments ?? 0)
        }
        .onAppear {
            loadVideo()
        }
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
        VideoView(index: 0)
            .environmentObject(AuthenticationState())
    }
} 