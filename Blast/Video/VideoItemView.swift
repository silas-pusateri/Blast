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
    @Binding var showingDeleteConfirmation: Bool
    @Binding var videoToDelete: Video?
    
    var body: some View {
        VideoView(video: video)
            .frame(
                width: geometry.size.width,
                height: geometry.size.height
            )
            .id(index)
            .onLongPressGesture {
                if video.userId == Auth.auth().currentUser?.uid {
                    videoToDelete = video
                    showingDeleteConfirmation = true
                }
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

// New struct for video list content
struct VideoListContent: View {
    let geometry: GeometryProxy
    @EnvironmentObject var videoViewModel: VideoViewModel
    @Binding var showingDeleteConfirmation: Bool
    @Binding var videoToDelete: Video?
    
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
                    videoToDelete: $videoToDelete
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
    
    var body: some View {
        GeometryReader { geometry in
            ScrollView(.vertical, showsIndicators: false) {
                RefreshableView(
                    isRefreshing: $isRefreshing,
                    onRefresh: {
                        currentVideoIndex = 0
                        await videoViewModel.fetchVideos(isRefresh: true)
                        isRefreshing = false
                    }
                ) {
                    VideoListContent(
                        geometry: geometry,
                        showingDeleteConfirmation: $showingDeleteConfirmation,
                        videoToDelete: $videoToDelete
                    )
                }
            }
            .scrollTargetBehavior(.paging)
            .scrollTargetLayout()
        }
    }
}
