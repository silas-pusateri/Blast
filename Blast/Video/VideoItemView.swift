//
//  VideoItemView.swift
//  Blast
//
//  Created by Silas Pusateri on 2/6/25.
//

import SwiftUI
import FirebaseAuth
import AVKit
import FirebaseFirestore
import Combine

// New struct for individual video item
struct VideoItemView: View {
    let video: Video
    let index: Int
    let geometry: GeometryProxy
    let isLastVideo: Bool
    @EnvironmentObject var videoViewModel: VideoViewModel
    @EnvironmentObject var authState: AuthenticationState
    @Binding var showingDeleteConfirmation: Bool
    @Binding var videoToDelete: Video?
    @Binding var showingLogoutConfirmation: Bool
    @State private var showingOptionsSheet = false
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            VideoView(video: video, videoViewModel: videoViewModel)
                .frame(
                    width: geometry.size.width,
                    height: geometry.size.height
                )
                .id(index)
        }
        .onLongPressGesture {
            showingOptionsSheet = true
        }
        .sheet(isPresented: $showingOptionsSheet) {
            VideoOptionsSheet(
                video: video,
                videoViewModel: videoViewModel,
                showingDeleteConfirmation: $showingDeleteConfirmation,
                videoToDelete: $videoToDelete,
                showingLogoutConfirmation: $showingLogoutConfirmation,
                showingOptionsSheet: $showingOptionsSheet
            )
            .presentationDetents([.height(250)])
        }
        .onAppear {
            handleVideoAppearance()
        }
    }
    
    private func handleVideoAppearance() {
        // Load more videos if this is the last one
        if isLastVideo {
            Task {
                await videoViewModel.fetchVideos()
            }
        }
        
        // Preload next video when current one appears
        if index < videoViewModel.videos.count {
            let currentVideo = videoViewModel.videos[index]
            VideoPreloadManager.shared.preloadNextVideo(
                currentVideo: currentVideo,
                videos: videoViewModel.videos
            )
        }
    }
}

// New struct for options sheet
struct VideoOptionsSheet: View {
    let video: Video
    let videoViewModel: VideoViewModel
    @Binding var showingDeleteConfirmation: Bool
    @Binding var videoToDelete: Video?
    @Binding var showingLogoutConfirmation: Bool
    @Binding var showingOptionsSheet: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var showingSuggestChanges = false
    @State private var showingChangesReview = false
    @State private var showingProfile = false
    @State private var profileUserId: String?
    
    var body: some View {
        NavigationView {
            List {
                // View video creator's profile
                Button {
                    profileUserId = video.userId
                    showingProfile = true
                } label: {
                    Label("View Creator", systemImage: "person.circle")
                        .foregroundColor(.primary)
                }
                
                // View current user's profile
                if let currentUserId = Auth.auth().currentUser?.uid {
                    Button {
                        profileUserId = currentUserId
                        showingProfile = true
                    } label: {
                        Label("My Profile", systemImage: "person.circle.fill")
                            .foregroundColor(.primary)
                    }
                }
                
                // Only show Suggest Changes if not the video owner
                if video.userId != Auth.auth().currentUser?.uid {
                    Button {
                        showingSuggestChanges = true
                    } label: {
                        Label("Suggest Changes", systemImage: "pencil.and.outline")
                            .foregroundColor(.primary)
                    }
                } else {
                    // Show View Changes button for video owner
                    Button {
                        showingChangesReview = true
                    } label: {
                        Label("View Changes", systemImage: "list.bullet.clipboard")
                            .foregroundColor(.primary)
                    }
                }
                
                if video.userId == Auth.auth().currentUser?.uid {
                    Button(role: .destructive) {
                        videoToDelete = video
                        showingDeleteConfirmation = true
                        showingOptionsSheet = false
                    } label: {
                        Label {
                            Text("Delete Video")
                                .foregroundColor(.red)
                        } icon: {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                    }
                }
                
                Button(role: .destructive) {
                    showingLogoutConfirmation = true
                    showingOptionsSheet = false
                } label: {
                    Label("Logout", systemImage: "rectangle.portrait.and.arrow.right")
                        .foregroundColor(.red)
                }
            }
            .navigationTitle("Video Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        showingOptionsSheet = false
                    }
                }
            }
        }
        .sheet(isPresented: $showingSuggestChanges) {
            SuggestChangesView(video: video, videoViewModel: videoViewModel)
        }
        .sheet(isPresented: $showingChangesReview) {
            ChangesReviewView(video: video, videoViewModel: videoViewModel)
        }
        .sheet(isPresented: $showingProfile) {
            if let userId = profileUserId {
                ProfileView(userId: userId)
            }
        }
    }
}

// New struct for video list content
struct VideoListContent: View {
    let geometry: GeometryProxy
    @EnvironmentObject var videoViewModel: VideoViewModel
    @Binding var showingDeleteConfirmation: Bool
    @Binding var videoToDelete: Video?
    @Binding var showingLogoutConfirmation: Bool
    
    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(videoViewModel.videos.indices, id: \.self) { index in
                let video = videoViewModel.videos[index]
                VideoItemView(
                    video: video,
                    index: index,
                    geometry: geometry,
                    isLastVideo: video.id == videoViewModel.videos.last?.id,
                    showingDeleteConfirmation: $showingDeleteConfirmation,
                    videoToDelete: $videoToDelete,
                    showingLogoutConfirmation: $showingLogoutConfirmation
                )
            }
            
            if videoViewModel.isLoading {
                LoadingIndicator(geometry: geometry)
            }
        }
    }
}

// New struct for loading indicator
struct LoadingIndicator: View {
    let geometry: GeometryProxy
    
    var body: some View {
        ProgressView()
            .frame(width: geometry.size.width, height: 50)
            .foregroundColor(.white)
    }
}

// Refactored VideoScrollView
struct VideoScrollView: View {
    @EnvironmentObject var videoViewModel: VideoViewModel
    @Binding var currentVideoIndex: Int
    @Binding var showingDeleteConfirmation: Bool
    @Binding var videoToDelete: Video?
    @Binding var isRefreshing: Bool
    @Binding var showingLogoutConfirmation: Bool
    
    var body: some View {
        GeometryReader { geometry in
            ScrollView(.vertical, showsIndicators: false) {
                RefreshableView(
                    isRefreshing: $isRefreshing,
                    onRefresh: {
                        currentVideoIndex = 0
                        await videoViewModel.fetchVideos(isRefresh: true)
                        
                        // Preload first two videos after refresh
                        if let firstVideo = videoViewModel.videos.first {
                            VideoPreloadManager.shared.preloadVideo(video: firstVideo)
                            if let secondVideo = videoViewModel.videos.dropFirst().first {
                                VideoPreloadManager.shared.preloadVideo(video: secondVideo)
                            }
                        }
                        isRefreshing = false
                    }
                ) {
                    VideoListContent(
                        geometry: geometry,
                        showingDeleteConfirmation: $showingDeleteConfirmation,
                        videoToDelete: $videoToDelete,
                        showingLogoutConfirmation: $showingLogoutConfirmation
                    )
                }
            }
            .scrollTargetBehavior(.paging)
            .scrollTargetLayout()
        }
    }
}

// New struct for video tag
struct VideoTag: View {
    let isEdited: Bool
    
    var body: some View {
        Text(isEdited ? "Edited Video" : "Original Video")
            .font(.caption)
            .fontWeight(.medium)
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isEdited ? Color.blue.opacity(0.8) : Color.green.opacity(0.8))
            .cornerRadius(4)
    }
}
