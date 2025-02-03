import SwiftUI
import AVKit

struct VideoView: View {
    let index: Int
    @State private var isShowingComments = false
    @State private var isLiked = false
    @State private var likes = Int.random(in: 100...10000)
    private let player: AVPlayer
    
    init(index: Int) {
        self.index = index
        // Replace with actual video URL when available
        let videoURL = URL(string: "https://example.com/video\(index).mp4")!
        self.player = AVPlayer(url: videoURL)
    }
    
    var body: some View {
        ZStack {
            Color.black
            
            AVPlayerControllerRepresented(player: player)
                .disabled(true)
            
            VStack {
                Spacer()
                
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("@username\(index)")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Video caption goes here #viral #trending")
                            .font(.system(size: 14, weight: .regular))
                            .lineLimit(2)
                    }
                    .foregroundColor(.white)
                    
                    Spacer()
                    
                    VStack(spacing: 20) {
                        Button(action: {
                            isLiked.toggle()
                            likes += isLiked ? 1 : -1
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
                                Text("\(Int.random(in: 10...1000))")
                                    .foregroundColor(.white)
                                    .font(.system(size: 12))
                            }
                        }
                        
                        Button(action: {
                            // Share action
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
        .sheet(isPresented: $isShowingComments) {
            CommentView(commentCount: Int.random(in: 1...20))
        }
    }
}

struct AVPlayerControllerRepresented: UIViewControllerRepresentable {
    let player: AVPlayer
    
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false
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