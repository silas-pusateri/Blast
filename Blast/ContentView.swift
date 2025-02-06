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
import AVKit

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
    @StateObject private var videoViewModel = VideoViewModel()
    @State private var showingUploadView = false
    @State private var isRefreshing = false
    @State private var currentVideoIndex = 0
    @State private var showingDeleteConfirmation = false
    @State private var videoToDelete: Video?
    
    var body: some View {
        if !authState.isSignedIn {
            LoginView()
                .edgesIgnoringSafeArea(.all)
        } else {
            MainContentView(
                showingUploadView: $showingUploadView,
                isRefreshing: $isRefreshing,
                currentVideoIndex: $currentVideoIndex,
                showingDeleteConfirmation: $showingDeleteConfirmation,
                videoToDelete: $videoToDelete
            )
            .environmentObject(videoViewModel)
            .edgesIgnoringSafeArea(.all)
        }
    }
}

// New struct to handle main content
struct MainContentView: View {
    @EnvironmentObject var videoViewModel: VideoViewModel
    @Binding var showingUploadView: Bool
    @Binding var isRefreshing: Bool
    @Binding var currentVideoIndex: Int
    @Binding var showingDeleteConfirmation: Bool
    @Binding var videoToDelete: Video?
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            VideoScrollView(
                currentVideoIndex: $currentVideoIndex,
                showingDeleteConfirmation: $showingDeleteConfirmation,
                videoToDelete: $videoToDelete,
                isRefreshing: $isRefreshing
            )
            
            TopButtonsView(
                showingUploadView: $showingUploadView,
                isRefreshing: $isRefreshing,
                currentVideoIndex: $currentVideoIndex
            )
        }
        .edgesIgnoringSafeArea(.all)
        .sheet(isPresented: $showingUploadView) {
            // Refresh feed when returning from upload
            Task {
                currentVideoIndex = 0
                await videoViewModel.fetchVideos(isRefresh: true)
                if let firstVideo = videoViewModel.videos.first {
                    VideoPreloadManager.shared.preloadVideo(video: firstVideo)
                }
                if let secondVideo = videoViewModel.videos.dropFirst().first {
                    VideoPreloadManager.shared.preloadVideo(video: secondVideo)
                }
            }
        } content: {
            UploadView()
                .environmentObject(videoViewModel)
        }
        .confirmationDialog(
            "Delete Video",
            isPresented: $showingDeleteConfirmation,
            presenting: videoToDelete
        ) { video in
            Button("Delete", role: .destructive) {
                Task {
                    do {
                        try await videoViewModel.deleteVideo(video)
                    } catch {
                        print("Error deleting video: \(error)")
                    }
                }
            }
        } message: { video in
            Text("Are you sure you want to delete this video? This action cannot be undone.")
        }
        .task {
            await videoViewModel.fetchVideos(isRefresh: true)
            if let firstVideo = videoViewModel.videos.first {
                VideoPreloadManager.shared.preloadVideo(video: firstVideo)
            }
            if let secondVideo = videoViewModel.videos.dropFirst().first {
                VideoPreloadManager.shared.preloadVideo(video: secondVideo)
            }
        }
    }
}

// New struct for top buttons
struct TopButtonsView: View {
    @Binding var showingUploadView: Bool
    @Binding var isRefreshing: Bool
    @EnvironmentObject var videoViewModel: VideoViewModel
    @Binding var currentVideoIndex: Int
    
    var body: some View {
        HStack {
            RefreshButton(
                isRefreshing: $isRefreshing,
                currentVideoIndex: $currentVideoIndex
            )
            
            Spacer()
            
            UploadButton(showingUploadView: $showingUploadView)
        }
        .padding(.top, 60)
        .padding(.horizontal, 16)
    }
}

// New struct for refresh button
struct RefreshButton: View {
    @Binding var isRefreshing: Bool
    @EnvironmentObject var videoViewModel: VideoViewModel
    @Binding var currentVideoIndex: Int
    
    var body: some View {
        Button(action: {
            isRefreshing = true
            Task {
                currentVideoIndex = 0
                await videoViewModel.fetchVideos(isRefresh: true)
                isRefreshing = false
            }
        }) {
            Image(systemName: "arrow.clockwise")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(Color.black.opacity(0.5))
                .clipShape(Circle())
        }
    }
}

// New struct for upload button
struct UploadButton: View {
    @Binding var showingUploadView: Bool
    
    var body: some View {
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

// Extension to format dates
extension Date {
    func timeAgo() -> String {
        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: self, to: now)
        
        if let year = components.year, year >= 1 {
            return "\(year)y"
        } else if let month = components.month, month >= 1 {
            return "\(month)mo"
        } else if let day = components.day, day >= 1 {
            return "\(day)d"
        } else if let hour = components.hour, hour >= 1 {
            return "\(hour)h"
        } else if let minute = components.minute, minute >= 1 {
            return "\(minute)m"
        } else {
            return "now"
        }
    }
}

/// Separate small subview to choose source (camera/gallery).
struct VideoSourceSelectionView: View {
    @Binding var showingCameraView: Bool
    @Binding var photoPickerItem: PhotosPickerItem?
    
    var body: some View {
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
                    PhotosPicker(
                        selection: $photoPickerItem,
                        matching: .videos,
                        photoLibrary: .shared()
                    ) {
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

struct VideoPreviewArea: View {
    @Binding var selectedVideo: URL?
    @Binding var isLoadingVideo: Bool
    @Binding var showingCameraView: Bool
    @Binding var photoPickerItem: PhotosPickerItem?
    @State private var player: AVPlayer?
    @State private var showingEditor = false
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.2))
                .aspectRatio(9/16, contentMode: .fit)
                .padding(.horizontal)
            
            if isLoadingVideo {
                ProgressView("Loading video...")
            } else if let videoURL = selectedVideo {
                ZStack(alignment: .topTrailing) {
                    VideoPlayer(player: AVPlayer(url: videoURL))
                        .aspectRatio(9/16, contentMode: .fit)
                        .cornerRadius(12)
                        .padding(.horizontal)
                        .onAppear {
                            // Create and store player when view appears
                            player = AVPlayer(url: videoURL)
                            player?.play()
                        }
                        .onDisappear {
                            // Cleanup player when view disappears
                            player?.pause()
                            player = nil
                        }
                    
                    Button(action: {
                        showingEditor = true
                    }) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                    }
                    .padding(.top, 20)
                    .padding(.trailing, 30)
                }
                .fullScreenCover(isPresented: $showingEditor) {
                    EditorView(videoURL: videoURL) { editedVideoURL in
                        // Update the selected video with the edited version
                        selectedVideo = editedVideoURL
                    }
                }
            } else {
                // If no video selected, show the source selection UI
                VideoSourceSelectionView(showingCameraView: $showingCameraView, photoPickerItem: $photoPickerItem)
            }
        }
    }
}

// Add VideoCompressor class before UploadView
class VideoCompressor {
    static func compressVideo(inputURL: URL, completion: @escaping (Result<URL, Error>) -> Void) {
        let compressionName = UUID().uuidString
        let compressedURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(compressionName).mp4")
        
        // Setup export session with higher quality compression preset
        let asset = AVAsset(url: inputURL)
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1920x1080) else {
            completion(.failure(NSError(domain: "VideoCompressor", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not create export session"])))
            return
        }
        
        // Configure export session
        exportSession.outputURL = compressedURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true
        
        // Start compression
        exportSession.exportAsynchronously {
            DispatchQueue.main.async {
                if let error = exportSession.error {
                    completion(.failure(error))
                } else if let compressedURL = exportSession.outputURL {
                    completion(.success(compressedURL))
                } else {
                    completion(.failure(NSError(domain: "VideoCompressor", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown compression error"])))
                }
            }
        }
    }
}

struct UploadView: View {
    @Environment(\.dismiss) var dismiss
    
    // MARK: - State
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
        "Drop a ❤️ if you relate to this!"
    ]
    
    // MARK: - Body
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                
                // 1) Video preview / selection area
                VideoPreviewArea(
                    selectedVideo: $selectedVideo,
                    isLoadingVideo: $isLoadingVideo,
                    showingCameraView: $showingCameraView,
                    photoPickerItem: $photoPickerItem
                )
                
                // 2) Caption input (with AI generation)
                CaptionInputSection(
                    caption: $caption,
                    isGeneratingCaption: $isGeneratingCaption,
                    generateAICaption: generateAICaption
                )
                
                // Show any errors
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding(.horizontal)
                }
                
                // 3) Upload button with progress
                UploadProgressButton(
                    selectedVideo: $selectedVideo,
                    isUploading: $isUploading,
                    uploadProgress: $uploadProgress,
                    action: uploadVideo
                )
                
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
                if let newValue, 
                   let videoData = try? await newValue.loadTransferable(type: VideoTransferData.self) {
                    let fileName = "\(UUID().uuidString).mov"
                    let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
                    try? videoData.data.write(to: fileURL)
                    selectedVideo = fileURL
                }
                isLoadingVideo = false
            }
        }
    }
    
    // MARK: - Functions
    
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
        
        // Start compression
        VideoCompressor.compressVideo(inputURL: videoURL) { result in
            switch result {
            case .success(let compressedURL):
                // Create a unique filename
                let filename = "\(UUID().uuidString).mp4"
                let storageRef = Storage.storage().reference().child("videos/\(filename)")
                
                // Create metadata
                let metadata = StorageMetadata()
                metadata.contentType = "video/mp4"
                
                // Start upload task
                let uploadTask = storageRef.putFile(from: compressedURL, metadata: metadata)
                
                // Monitor upload progress
                uploadTask.observe(.progress) { snapshot in
                    let percentComplete = Double(snapshot.progress?.completedUnitCount ?? 0) /
                                          Double(snapshot.progress?.totalUnitCount ?? 1)
                    DispatchQueue.main.async {
                        self.uploadProgress = percentComplete
                    }
                }
                
                // Handle upload completion
                uploadTask.observe(.success) { _ in
                    storageRef.downloadURL { url, error in
                        DispatchQueue.main.async {
                            if let error = error {
                                self.errorMessage = "Failed to get download URL: \(error.localizedDescription)"
                                self.isUploading = false
                                return
                            }
                            
                            guard let downloadURL = url else {
                                self.errorMessage = "Failed to get download URL"
                                self.isUploading = false
                                return
                            }
                            
                            // Save video metadata to Firestore
                            let db = Firestore.firestore()
                            let videoData: [String: Any] = [
                                "userId": Auth.auth().currentUser?.uid ?? "",
                                "caption": self.caption,
                                "videoUrl": downloadURL.absoluteString,
                                "timestamp": FieldValue.serverTimestamp(),
                                "likes": 0,
                                "comments": 0
                            ]
                            
                            db.collection("videos").addDocument(data: videoData) { error in
                                DispatchQueue.main.async {
                                    self.isUploading = false
                                    if let error = error {
                                        self.errorMessage = "Failed to save video metadata: \(error.localizedDescription)"
                                    } else {
                                        // Clean up compressed file
                                        try? FileManager.default.removeItem(at: compressedURL)
                                        self.dismiss()
                                    }
                                }
                            }
                        }
                    }
                }
                
                uploadTask.observe(.failure) { snapshot in
                    DispatchQueue.main.async {
                        self.isUploading = false
                        self.errorMessage = snapshot.error?.localizedDescription ?? "Upload failed"
                        // Clean up compressed file on failure
                        try? FileManager.default.removeItem(at: compressedURL)
                    }
                }
                
            case .failure(let error):
                DispatchQueue.main.async {
                    self.isUploading = false
                    self.errorMessage = "Compression failed: \(error.localizedDescription)"
                }
            }
        }
    }
}

struct CaptionInputSection: View {
    @Binding var caption: String
    @Binding var isGeneratingCaption: Bool
    var generateAICaption: () -> Void
    
    var body: some View {
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
                    
                    let buttonText = isGeneratingCaption ? "Thinking..." : "Generate AI Caption"
                    Text(buttonText)
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
    }
}

struct UploadProgressButton: View {
    @Binding var selectedVideo: URL?
    @Binding var isUploading: Bool
    @Binding var uploadProgress: Double
    
    var action: () -> Void
    
    var body: some View {
        Button(action: {
            action()
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
