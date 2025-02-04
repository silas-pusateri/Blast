import SwiftUI
import AVKit
import FirebaseFirestore
import FirebaseStorage


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
                
                // Create decoder with document path
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