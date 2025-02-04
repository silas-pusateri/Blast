//
//  ContentView.swift
//  Blast
//
//  Created by Silas Pusateri on 2/3/25.
//

import SwiftUI
import AVFoundation
import PhotosUI
import FirebaseAuth
import FirebaseStorage
import FirebaseFirestore
import os

struct LoginView: View {
    @EnvironmentObject private var authState: AuthenticationState
    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = false
    @State private var errorMessage = ""
    @State private var isLoading = false
    
    // Modify logger initialization to be preview-safe
    #if DEBUG
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.blast", category: "viewCycle")
    #else
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.blast", category: "viewCycle")
    #endif
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Logo/Title
                Text("Blast")
                    .font(.system(size: 40, weight: .bold))
                    .padding(.top, 50)
                
                // Error message
                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding(.horizontal)
                }
                
                // Input fields
                VStack(spacing: 15) {
                    TextField("Email", text: $email)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                    
                    SecureField("Password", text: $password)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                .padding(.horizontal, 32)
                
                // Login/SignUp Button
                Button(action: {
                    isLoading = true
                    errorMessage = ""
                    
                    if isSignUp {
                        // Sign Up
                        Auth.auth().createUser(withEmail: email, password: password) { result, error in
                            handleAuthResult(error)
                        }
                    } else {
                        // Login
                        Auth.auth().signIn(withEmail: email, password: password) { result, error in
                            handleAuthResult(error)
                        }
                    }
                }) {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Text(isSignUp ? "Sign Up" : "Log In")
                    }
                }
                .frame(width: 200, height: 50)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(25)
                .disabled(isLoading)
                
                // Toggle Login/SignUp
                Button(action: {
                    isSignUp.toggle()
                    errorMessage = ""
                }) {
                    Text(isSignUp ? "Already have an account? Log in" : "Don't have an account? Sign up")
                        .foregroundColor(.blue)
                }
                .padding(.top)
                
                Spacer()
            }
            .navigationBarHidden(true)
        }
    }
    
    private func handleAuthResult(_ error: Error?) {
        isLoading = false
        
        if let error = error {
            #if DEBUG
            // In debug mode (including previews), also print to console
            print("🔴 Raw error object: \(String(describing: error))")
            
            if let nsError = error as NSError? {
                print("""
                    🔴 Detailed error information:
                    Domain: \(nsError.domain)
                    Code: \(nsError.code)
                    Description: \(nsError.localizedDescription)
                    User Info: \(nsError.userInfo)
                    """)
            }
            
            if let authError = error as? AuthErrorCode {
                print("""
                    🔴 Firebase Auth error details:
                    Error Code: \(authError.code)
                    Raw Value: \(authError.code.rawValue)
                    Message: \(authError.localizedDescription)
                    """)
            }
            #endif
            
            // Use logger for release builds
            logger.error("🔴 Raw error object: \(String(describing: error))")
            
            if let nsError = error as NSError? {
                logger.error("""
                    🔴 Detailed error information:
                    Domain: \(nsError.domain)
                    Code: \(nsError.code)
                    Description: \(nsError.localizedDescription)
                    User Info: \(nsError.userInfo)
                    """)
            }
            
            errorMessage = error.localizedDescription
        }
        // No need to set isLoggedIn manually anymore as it's handled by AuthenticationState
    }
}

struct ContentView: View {
    @EnvironmentObject private var authState: AuthenticationState
    @State private var showingUploadView = false
    @State private var isRefreshing = false
    
    var body: some View {
        if !authState.isSignedIn {
            LoginView()
        } else {
            // Main app content
            ZStack(alignment: .topTrailing) {
                GeometryReader { geometry in
                    ScrollView(.vertical, showsIndicators: false) {
                        RefreshableView(
                            isRefreshing: $isRefreshing,
                            onRefresh: {
                                // Simulate refresh delay
                                try? await Task.sleep(nanoseconds: 1_000_000_000)
                                isRefreshing = false
                            }
                        ) {
                            LazyVStack(spacing: 0) {
                                ForEach(0..<5) { index in
                                    VideoView(index: index)
                                        .frame(width: geometry.size.width,
                                               height: geometry.size.height)
                                }
                            }
                        }
                    }
                    .scrollTargetBehavior(.paging)
                }
                
                // Upload button
                Button(action: {
                    showingUploadView = true
                }) {
                    Image(systemName: "plus")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.black.opacity(0.5))
                        .clipShape(Circle())
                }
                .padding(.top, 60)
                .padding(.trailing, 16)
            }
            .edgesIgnoringSafeArea(.all)
            .sheet(isPresented: $showingUploadView) {
                UploadView()
            }
        }
    }
}

// Custom RefreshableView implementation
struct RefreshableView<Content: View>: View {
    @Binding var isRefreshing: Bool
    let onRefresh: () async throws -> Void
    let content: Content
    @State private var offset: CGFloat = 0
    private let threshold: CGFloat = 50
    
    init(
        isRefreshing: Binding<Bool>,
        onRefresh: @escaping () async throws -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self._isRefreshing = isRefreshing
        self.onRefresh = onRefresh
        self.content = content()
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: OffsetPreferenceKey.self,
                    value: geometry.frame(in: .named("scrollView")).minY
                )
            }
            .frame(height: 0)
            
            content
        }
        .coordinateSpace(name: "scrollView")
        .onPreferenceChange(OffsetPreferenceKey.self) { offset in
            self.offset = offset
            
            if offset > threshold && !isRefreshing {
                isRefreshing = true
                Task {
                    try? await onRefresh()
                }
            }
        }
        .overlay(alignment: .top) {
            if isRefreshing {
                ProgressView()
                    .tint(.white)
                    .frame(height: 50)
            } else if offset > 0 {
                // Pull indicator
                Image(systemName: "arrow.down")
                    .foregroundColor(.white)
                    .frame(height: 50)
                    .opacity(Double(min(offset / threshold, 1.0)))
                    .rotationEffect(.degrees(Double(min((offset / threshold) * 180, 180))))
            }
        }
    }
}

// Preference key for tracking scroll offset
private struct OffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct CommentView: View {
    @Environment(\.dismiss) var dismiss
    let commentCount: Int
    @State private var newComment = ""
    
    var body: some View {
        NavigationView {
            VStack {
                List {
                    ForEach(0..<commentCount, id: \.self) { index in
                        CommentRow()
                    }
                }
                
                // Comment input area
                HStack(spacing: 12) {
                    Image(systemName: "person.circle.fill")
                        .resizable()
                        .frame(width: 32, height: 32)
                        .foregroundColor(.gray)
                    
                    TextField("Add a comment...", text: $newComment)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    Button(action: {
                        // Add comment logic here
                        if !newComment.isEmpty {
                            newComment = ""
                            // Hide keyboard
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                                         to: nil, from: nil, for: nil)
                        }
                    }) {
                        Text("Post")
                            .fontWeight(.semibold)
                            .foregroundColor(!newComment.isEmpty ? .blue : .gray)
                    }
                    .disabled(newComment.isEmpty)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(UIColor.systemBackground))
                .overlay(
                    Rectangle()
                        .frame(height: 0.5)
                        .foregroundColor(Color(UIColor.systemGray3)),
                    alignment: .top
                )
            }
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct CommentRow: View {
    let username = "@user\(Int.random(in: 100...999))"
    let comment = [
        "Love this! 🔥",
        "Amazing content!",
        "Keep it up! 👏",
        "This is incredible",
        "Can't stop watching this",
    ].randomElement()!
    @State private var likes: Int
    @State private var isLiked = false
    @State private var showReplies = false
    @State private var replyText = ""
    let replies = Int.random(in: 0...5)
    
    init() {
        _likes = State(initialValue: Int.random(in: 1...1000))
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Main comment
            HStack(alignment: .top) {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .frame(width: 40, height: 40)
                    .foregroundColor(.gray)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(username)
                        .font(.system(size: 14, weight: .semibold))
                    Text(comment)
                        .font(.system(size: 14))
                    
                    // Comment actions
                    HStack(spacing: 16) {
                        Text("2h")
                            .foregroundColor(.gray)
                            .font(.system(size: 12))
                        
                        if replies > 0 {
                            Button(action: { showReplies.toggle() }) {
                                Text("View \(replies) replies")
                                    .foregroundColor(.gray)
                                    .font(.system(size: 12))
                            }
                            .buttonStyle(BorderlessButtonStyle())
                        } else {
                            Button(action: { showReplies = true }) {
                                Text("Reply")
                                    .foregroundColor(.gray)
                                    .font(.system(size: 12))
                            }
                            .buttonStyle(BorderlessButtonStyle())
                        }
                    }
                    .padding(.top, 4)
                }
                
                Spacer()
                
                VStack(spacing: 4) {
                    Button(action: {
                        isLiked.toggle()
                        likes += isLiked ? 1 : -1
                    }) {
                        Image(systemName: isLiked ? "heart.fill" : "heart")
                            .foregroundColor(isLiked ? .red : .gray)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    
                    Text("\(likes)")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }
            }
            
            // Replies section
            if showReplies {
                VStack(spacing: 12) {
                    // Existing replies
                    ForEach(0..<replies, id: \.self) { _ in
                        ReplyRow()
                    }
                    
                    // Reply input
                    HStack(spacing: 8) {
                        Image(systemName: "person.circle.fill")
                            .resizable()
                            .frame(width: 24, height: 24)
                            .foregroundColor(.gray)
                        
                        TextField("Add a reply...", text: $replyText)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .font(.system(size: 12))
                        
                        Button(action: {
                            if !replyText.isEmpty {
                                replyText = ""
                                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                                             to: nil, from: nil, for: nil)
                            }
                        }) {
                            Text("Reply")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(!replyText.isEmpty ? .blue : .gray)
                        }
                        .buttonStyle(BorderlessButtonStyle())
                        .disabled(replyText.isEmpty)
                    }
                }
                .padding(.leading, 48)
            }
        }
        .padding(.vertical, 8)
    }
}

struct ReplyRow: View {
    let username = "@user\(Int.random(in: 100...999))"
    let reply = [
        "Totally agree!",
        "Nice one 👍",
        "Exactly!",
        "Well said",
        "100%",
    ].randomElement()!
    @State private var likes: Int
    @State private var isLiked = false
    
    init() {
        _likes = State(initialValue: Int.random(in: 1...100))
    }
    
    var body: some View {
        HStack(alignment: .top) {
            Image(systemName: "person.circle.fill")
                .resizable()
                .frame(width: 24, height: 24)
                .foregroundColor(.gray)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(username)
                    .font(.system(size: 12, weight: .semibold))
                Text(reply)
                    .font(.system(size: 12))
                Text("1h")
                    .foregroundColor(.gray)
                    .font(.system(size: 10))
                    .padding(.top, 2)
            }
            
            Spacer()
            
            VStack(spacing: 2) {
                Button(action: {
                    isLiked.toggle()
                    likes += isLiked ? 1 : -1
                }) {
                    Image(systemName: isLiked ? "heart.fill" : "heart")
                        .foregroundColor(isLiked ? .red : .gray)
                        .scaleEffect(0.8)
                }
                .buttonStyle(BorderlessButtonStyle())
                
                Text("\(likes)")
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
            }
        }
    }
}

struct UploadView: View {
    @Environment(\.dismiss) var dismiss
    @State private var selectedVideo: URL?
    @State private var showingVideoPicker = false
    @State private var showingCameraView = false
    @State private var caption = ""
    @State private var isGeneratingCaption = false
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var isLoadingVideo = false
    @State private var isUploading = false
    @State private var uploadProgress: Double = 0
    @State private var errorMessage: String?
    
    // Sample AI-generated captions
    let aiCaptions = [
        "✨ Living my best life! #trending #viral",
        "🔥 Watch until the end! You won't believe what happens",
        "This moment was too good not to share 😊 #memories",
        "POV: When the weekend finally arrives 🎉",
        "Drop a ❤️ if you relate to this!",
    ]
    
    func generateAICaption() {
        isGeneratingCaption = true
        
        // Simulate AI processing with delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            caption = aiCaptions.randomElement() ?? ""
            isGeneratingCaption = false
        }
    }
    
    private func uploadVideo() {
        guard let videoURL = selectedVideo else { return }
        isUploading = true
        errorMessage = nil
        
        // Create a unique filename
        let filename = "\(UUID().uuidString).mov"
        let storageRef = Storage.storage().reference().child("videos/\(filename)")
        
        // Create metadata
        let metadata = StorageMetadata()
        metadata.contentType = "video/quicktime"
        
        // Start upload task
        let uploadTask = storageRef.putFile(from: videoURL, metadata: metadata)
        
        // Monitor upload progress
        uploadTask.observe(.progress) { snapshot in
            let percentComplete = Double(snapshot.progress?.completedUnitCount ?? 0) / Double(snapshot.progress?.totalUnitCount ?? 1)
            DispatchQueue.main.async {
                uploadProgress = percentComplete
            }
        }
        
        // Handle upload completion
        uploadTask.observe(.success) { _ in
            // Get download URL
            storageRef.downloadURL { url, error in
                DispatchQueue.main.async {
                    if let error = error {
                        errorMessage = "Failed to get download URL: \(error.localizedDescription)"
                        isUploading = false
                        return
                    }
                    
                    guard let downloadURL = url else {
                        errorMessage = "Failed to get download URL"
                        isUploading = false
                        return
                    }
                    
                    // Save video metadata to Firestore
                    let db = Firestore.firestore()
                    let videoData: [String: Any] = [
                        "userId": Auth.auth().currentUser?.uid ?? "",
                        "caption": caption,
                        "videoUrl": downloadURL.absoluteString,
                        "timestamp": FieldValue.serverTimestamp(),
                        "likes": 0,
                        "comments": 0
                    ]
                    
                    db.collection("videos").addDocument(data: videoData) { error in
                        DispatchQueue.main.async {
                            isUploading = false
                            if let error = error {
                                errorMessage = "Failed to save video metadata: \(error.localizedDescription)"
                            } else {
                                dismiss()
                            }
                        }
                    }
                }
            }
        }
        
        uploadTask.observe(.failure) { snapshot in
            DispatchQueue.main.async {
                isUploading = false
                errorMessage = snapshot.error?.localizedDescription ?? "Upload failed"
            }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Video preview area
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.2))
                        .aspectRatio(9/16, contentMode: .fit)
                        .padding(.horizontal)
                    
                    if isLoadingVideo {
                        ProgressView("Loading video...")
                    } else if let videoURL = selectedVideo {
                        VideoPlayer(url: videoURL)
                            .aspectRatio(9/16, contentMode: .fit)
                            .cornerRadius(12)
                            .padding(.horizontal)
                    } else {
                        GeometryReader { geometry in
                            VStack(spacing: 20) {
                                Image(systemName: "video.badge.plus")
                                    .font(.system(size: 40))
                                    .foregroundColor(.gray)
                                    .padding(.top, geometry.size.height * 0.15)
                                
                                Text("Choose video source")
                                    .foregroundColor(.gray)
                                
                                Spacer()
                                
                                HStack(spacing: 20) {
                                    // Camera Button
                                    Button(action: {
                                        showingCameraView = true
                                    }) {
                                        VStack(spacing: 12) {
                                            Image(systemName: "camera.fill")
                                                .font(.system(size: 32))
                                            Text("Record")
                                                .font(.subheadline)
                                        }
                                        .foregroundColor(.white)
                                        .frame(width: 140, height: 140)
                                        .background(Color.blue)
                                        .cornerRadius(16)
                                    }
                                    
                                    // Gallery Button
                                    PhotosPicker(selection: $photoPickerItem,
                                               matching: .videos,
                                               photoLibrary: .shared()) {
                                        VStack(spacing: 12) {
                                            Image(systemName: "photo.fill")
                                                .font(.system(size: 32))
                                            Text("Gallery")
                                                .font(.subheadline)
                                        }
                                        .foregroundColor(.white)
                                        .frame(width: 140, height: 140)
                                        .background(Color.green)
                                        .cornerRadius(16)
                                    }
                                }
                                .padding(.bottom, geometry.size.height * 0.2)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }
                
                // Caption input with AI button
                VStack(alignment: .leading) {
                    Text("Caption")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    TextEditor(text: $caption)
                        .frame(height: 100)
                        .padding(2)
                        .background(Color(UIColor.systemGray6))
                        .cornerRadius(8)
                        .disabled(isGeneratingCaption)
                        .padding(.horizontal)
                    
                    Button(action: {
                        generateAICaption()
                    }) {
                        HStack(spacing: 4) {
                            if isGeneratingCaption {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "sparkles")
                            }
                            Text(isGeneratingCaption ? "Thinking..." : "Generate AI Caption")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(isGeneratingCaption ? Color.purple.opacity(0.7) : Color.purple)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    .disabled(isGeneratingCaption)
                    .padding(.horizontal)
                    
                    if isGeneratingCaption {
                        Text("AI is crafting the perfect caption...")
                            .font(.caption)
                            .foregroundColor(.purple)
                            .padding(.horizontal)
                            .padding(.top, 4)
                    }
                }
                
                if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding(.horizontal)
                }
                
                // Upload button with progress
                Button(action: {
                    uploadVideo()
                }) {
                    ZStack {
                        if isUploading {
                            ProgressView(value: uploadProgress) {
                                Text("Uploading... \(Int(uploadProgress * 100))%")
                                    .foregroundColor(.white)
                            }
                            .progressViewStyle(LinearProgressViewStyle(tint: .white))
                            .padding(.horizontal)
                        } else {
                            Text("Upload")
                                .fontWeight(.semibold)
                        }
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(selectedVideo != nil ? Color.blue : Color.gray)
                    .cornerRadius(25)
                    .padding(.horizontal)
                }
                .disabled(selectedVideo == nil || isUploading)
                
                Spacer()
            }
            .padding(.top)
            .navigationTitle("New Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showingCameraView) {
            CameraView(selectedVideo: $selectedVideo)
        }
        .onChange(of: photoPickerItem) { oldValue, newValue in
            Task {
                isLoadingVideo = true
                if let videoData = try? await newValue?.loadTransferable(type: VideoTransferData.self) {
                    let fileName = "\(UUID().uuidString).mov"
                    let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
                    try? videoData.data.write(to: fileURL)
                    selectedVideo = fileURL
                }
                isLoadingVideo = false
            }
        }
    }
}

struct VideoPlayer: View {
    let url: URL
    
    var body: some View {
        VideoPlayerUIView(url: url)
    }
}

struct VideoPlayerUIView: UIViewRepresentable {
    let url: URL
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let player = AVPlayer(url: url)
        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.frame = view.layer.bounds
        view.layer.addSublayer(playerLayer)
        player.play()
        
        // Loop video
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                                             object: player.currentItem, queue: .main) { _ in
            player.seek(to: CMTime.zero)
            player.play()
        }
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        if let playerLayer = uiView.layer.sublayers?.first as? AVPlayerLayer {
            playerLayer.frame = uiView.layer.bounds
        }
    }
}


struct CameraView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var selectedVideo: URL?
    @StateObject private var cameraManager = CameraManager()
    @State private var isRecording = false
    
    var body: some View {
        Group {
            if cameraManager.isSimulator {
                // Simulator view
                VStack {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 40))
                        .padding()
                    Text("Camera not available in Simulator")
                        .font(.headline)
                    Text("Please test this feature on a physical device")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .padding()
                    Button("Close") {
                        dismiss()
                    }
                    .padding()
                }
            } else {
                // Real device camera view
                ZStack {
                    CameraPreviewView(session: cameraManager.session)
                        .ignoresSafeArea()
                    
                    // Camera controls
                    VStack {
                        Spacer()
                        
                        HStack(spacing: 30) {
                            // Flip camera button
                            Button(action: {
                                cameraManager.switchCamera()
                            }) {
                                Image(systemName: "camera.rotate.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(.white)
                                    .frame(width: 60, height: 60)
                                    .background(Color.black.opacity(0.5))
                                    .clipShape(Circle())
                            }
                            
                            // Record button
                            Button(action: {
                                if isRecording {
                                    cameraManager.stopRecording()
                                } else {
                                    cameraManager.startRecording { url in
                                        selectedVideo = url
                                        dismiss()
                                    }
                                }
                                isRecording.toggle()
                            }) {
                                Circle()
                                    .stroke(Color.white, lineWidth: 4)
                                    .frame(width: 80, height: 80)
                                    .overlay(
                                        Circle()
                                            .fill(isRecording ? Color.red : Color.white)
                                            .frame(width: 70, height: 70)
                                    )
                            }
                            
                            // Close button
                            Button(action: {
                                dismiss()
                            }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 24))
                                    .foregroundColor(.white)
                                    .frame(width: 60, height: 60)
                                    .background(Color.black.opacity(0.5))
                                    .clipShape(Circle())
                            }
                        }
                        .padding(.bottom, 50)
                    }
                }
            }
        }
        .onAppear {
            cameraManager.checkPermissions()
            cameraManager.setupSession()
        }
    }
}

// Camera manager to handle AVFoundation functionality
class CameraManager: NSObject, ObservableObject {
    let session = AVCaptureSession()
    var videoDeviceInput: AVCaptureDeviceInput?
    let movieOutput = AVCaptureMovieFileOutput()
    @Published var isSimulator: Bool
    var recordingCompletion: ((URL) -> Void)?
    
    override init() {
        #if targetEnvironment(simulator)
        self.isSimulator = true
        #else
        self.isSimulator = false
        #endif
        super.init()
    }
    
    func checkPermissions() {
        if isSimulator { return }
        
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    DispatchQueue.main.async {
                        self.setupSession()
                    }
                }
            }
        default:
            break
        }
    }
    
    func setupSession() {
        if isSimulator { return }
        
        session.beginConfiguration()
        
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                       for: .video,
                                                       position: .back) else { return }
        
        do {
            videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
            if session.canAddInput(videoDeviceInput!) {
                session.addInput(videoDeviceInput!)
            }
            
            if session.canAddOutput(movieOutput) {
                session.addOutput(movieOutput)
            }
        } catch {
            print("Error setting up camera: \(error.localizedDescription)")
            return
        }
        
        session.commitConfiguration()
        
        DispatchQueue.global(qos: .userInitiated).async {
            self.session.startRunning()
        }
    }
    
    func switchCamera() {
        guard let currentInput = videoDeviceInput else { return }
        
        let currentPosition = currentInput.device.position
        let newPosition: AVCaptureDevice.Position = currentPosition == .back ? .front : .back
        
        guard let newDevice = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                     for: .video,
                                                     position: newPosition) else { return }
        
        session.beginConfiguration()
        session.removeInput(currentInput)
        
        do {
            let newVideoInput = try AVCaptureDeviceInput(device: newDevice)
            if session.canAddInput(newVideoInput) {
                session.addInput(newVideoInput)
                videoDeviceInput = newVideoInput
            }
        } catch {
            print("Error switching camera: \(error.localizedDescription)")
            session.addInput(currentInput)
        }
        
        session.commitConfiguration()
    }
    
    func startRecording(completion: @escaping (URL) -> Void) {
        recordingCompletion = completion
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let fileUrl = paths[0].appendingPathComponent("\(UUID().uuidString).mov")
        movieOutput.startRecording(to: fileUrl, recordingDelegate: self)
    }
    
    func stopRecording() {
        movieOutput.stopRecording()
    }
}

extension CameraManager: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput,
                   didFinishRecordingTo outputFileURL: URL,
                   from connections: [AVCaptureConnection],
                   error: Error?) {
        if error == nil {
            DispatchQueue.main.async {
                self.recordingCompletion?(outputFileURL)
            }
        }
    }
}

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: UIScreen.main.bounds)
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.frame = view.frame
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {}
}

// Preview Providers
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(AuthenticationState())
    }
}

struct LoginView_Previews: PreviewProvider {
    static var previews: some View {
        LoginView()
            .environmentObject(AuthenticationState())
    }
}

#Preview {
    ContentView()
}
