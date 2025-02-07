//
//  UploadView.swift
//  Blast
//
//  Created by Silas Pusateri on 2/6/25.
//

import SwiftUI
import PhotosUI
import FirebaseStorage
import FirebaseFirestore
import FirebaseAuth


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
                
                // 3) Button row
                HStack(spacing: 16) {
                    // AI Caption Button
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
                        .frame(height: 50)
                        .background(isGeneratingCaption ? Color.purple.opacity(0.7) : Color.purple)
                        .foregroundColor(.white)
                        .cornerRadius(16)
                    }
                    .disabled(isGeneratingCaption)
                    
                    // Upload Button
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
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(selectedVideo != nil ? Color.blue : Color.gray)
                        .cornerRadius(16)
                    }
                    .disabled(selectedVideo == nil || isUploading)
                }
                .padding(.horizontal)
                
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
        UploadCompressor.compressVideo(inputURL: videoURL) { result in
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
            TextEditor(text: $caption)
                .frame(height: 100)
                .padding(2)
                .background(Color(UIColor.systemGray6))
                .cornerRadius(8)
                .disabled(isGeneratingCaption)
                .padding(.horizontal)
                .overlay(
                    Group {
                        if caption.isEmpty {
                            Text("Caption")
                                .foregroundColor(.gray)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 8)
                        }
                    },
                    alignment: .topLeading
                )
            
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
