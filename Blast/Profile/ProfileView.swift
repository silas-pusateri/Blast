import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import AVFoundation

struct ProfileView: View {
    let userId: String
    @StateObject private var videoViewModel = VideoViewModel()
    @State private var username: String = ""
    @State private var isLoadingProfile = true
    @State private var errorMessage: String?
    @State private var showingLogoutConfirmation = false
    @State private var isRefreshing = false
    @State private var showingEditProfile = false
    @EnvironmentObject private var authState: AuthenticationState
    @Environment(\.dismiss) private var dismiss
    
    private var isCurrentUser: Bool {
        userId == Auth.auth().currentUser?.uid
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Profile Header
                        VStack(spacing: 16) {
                            // Profile Picture
                            Circle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 100, height: 100)
                                .overlay(
                                    Image(systemName: "person.fill")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 50, height: 50)
                                        .foregroundColor(.white)
                                )
                            
                            // Username
                            Text(username)
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            
                            if isCurrentUser {
                                Button(action: { showingEditProfile = true }) {
                                    Text("Edit Profile")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.black)
                                        .frame(width: 120, height: 36)
                                        .background(Color.white)
                                        .cornerRadius(18)
                                }
                            }
                        }
                        .padding(.top, 20)
                        
                        // Videos Grid
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 2) {
                            ForEach(videoViewModel.videos) { video in
                                NavigationLink(destination: VideoView(video: video, videoViewModel: videoViewModel)) {
                                    VideoThumbnail(video: video)
                                }
                            }
                        }
                        .padding(.horizontal, 2)
                        
                        if videoViewModel.isLoading {
                            ProgressView()
                                .tint(.white)
                                .frame(height: 50)
                        }
                    }
                }
                .refreshable {
                    isRefreshing = true
                    await videoViewModel.fetchVideosByUser(userId: userId, isRefresh: true)
                    isRefreshing = false
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isCurrentUser {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: { showingLogoutConfirmation = true }) {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .foregroundColor(.white)
                        }
                    }
                }
            }
        }
        .task {
            await fetchUserProfile()
            await videoViewModel.fetchVideosByUser(userId: userId, isRefresh: true)
        }
        .confirmationDialog(
            "Logout",
            isPresented: $showingLogoutConfirmation
        ) {
            Button("Logout", role: .destructive) {
                do {
                    try Auth.auth().signOut()
                    authState.isSignedIn = false
                } catch {
                    print("Error signing out: \(error)")
                }
            }
        } message: {
            Text("Are you sure you want to logout?")
        }
    }
    
    private func fetchUserProfile() async {
        isLoadingProfile = true
        
        let db = Firestore.firestore()
        do {
            let document = try await db.collection("users").document(userId).getDocument()
            if let data = document.data(), let fetchedUsername = data["username"] as? String {
                username = fetchedUsername
            } else {
                username = "User"
            }
        } catch {
            print("Error fetching user profile: \(error)")
            errorMessage = error.localizedDescription
            username = "User"
        }
        
        isLoadingProfile = false
    }
}

struct VideoThumbnail: View {
    let video: Video
    @State private var thumbnailImage: UIImage?
    @State private var isLoading = true
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let image = thumbnailImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.width)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: geometry.size.width, height: geometry.size.width)
                        .overlay {
                            if isLoading {
                                ProgressView()
                                    .tint(.white)
                            }
                        }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .task {
            await generateThumbnail()
        }
    }
    
    private func generateThumbnail() async {
        guard let videoURL = URL(string: video.url) else { return }
        
        do {
            let asset = AVAsset(url: videoURL)
            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true
            
            let cgImage = try await imageGenerator.image(at: CMTime.zero).image
            thumbnailImage = UIImage(cgImage: cgImage)
        } catch {
            print("Error generating thumbnail: \(error)")
        }
        
        isLoading = false
    }
}

struct ProfileView_Previews: PreviewProvider {
    static var previews: some View {
        ProfileView(userId: "preview_user_id")
            .environmentObject(AuthenticationState())
    }
} 