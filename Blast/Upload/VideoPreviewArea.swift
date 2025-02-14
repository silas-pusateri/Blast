//
//  VideoPreviewArea.swift
//  Blast
//
//  Created by Silas Pusateri on 2/6/25.
//

import SwiftUI
import AVKit
import PhotosUI

struct VideoPreviewArea: View {
    @Binding var selectedVideo: URL?
    @Binding var isLoadingVideo: Bool
    @Binding var showingCameraView: Bool
    @Binding var photoPickerItem: PhotosPickerItem?
    @Binding var isCaptionFocused: Bool
    @State private var player: AVPlayer?
    @State private var showingEditor = false
    @State private var isPreviewReady = false
    @State private var previewError: String?
    @State private var aspectRatio: CGFloat = 9/16  // Default aspect ratio
    
    private func setupVideoPreview(for url: URL) {
        print("🎥 [VideoPreviewArea] Setting up preview for URL: \(url)")
        
        // Create asset with options
        let assetOptions = [
            AVURLAssetPreferPreciseDurationAndTimingKey: true
        ]
        let asset = AVURLAsset(url: url, options: assetOptions)
        
        // Load the asset asynchronously
        Task {
            do {
                print("🎥 [VideoPreviewArea] Loading asset...")
                // Load duration and tracks to ensure asset is playable
                _ = try await asset.load(.duration)
                let tracks = try await asset.load(.tracks)
                
                // Verify we have video tracks
                guard let videoTrack = tracks.first(where: { $0.mediaType == .video }) else {
                    print("❌ [VideoPreviewArea] No video tracks found")
                    await MainActor.run {
                        previewError = "Invalid video file format"
                        isPreviewReady = false
                    }
                    return
                }
                
                // Get video dimensions and calculate aspect ratio
                let naturalSize = try await videoTrack.load(.naturalSize)
                let videoAspectRatio = naturalSize.width / naturalSize.height
                
                await MainActor.run {
                    self.aspectRatio = videoAspectRatio
                    print("🎥 [VideoPreviewArea] Creating player with aspect ratio: \(videoAspectRatio)")
                    let playerItem = AVPlayerItem(asset: asset)
                    let newPlayer = AVPlayer(playerItem: playerItem)
                    self.player = newPlayer
                    
                    // Setup video looping
                    NotificationCenter.default.addObserver(
                        forName: .AVPlayerItemDidPlayToEndTime,
                        object: playerItem,
                        queue: .main) { [weak newPlayer] _ in
                            newPlayer?.seek(to: .zero)
                            newPlayer?.play()
                        }
                    
                    isPreviewReady = true
                    newPlayer.play()
                }
            } catch {
                print("❌ [VideoPreviewArea] Failed to load asset: \(error)")
                await MainActor.run {
                    previewError = "Failed to load video: \(error.localizedDescription)"
                    isPreviewReady = false
                }
            }
        }
    }
    
    var body: some View {
        Group {
            if isLoadingVideo || selectedVideo != nil {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.2))
                        .aspectRatio(aspectRatio, contentMode: .fit)
                        .padding(.horizontal)
                    
                    if isLoadingVideo {
                        ProgressView("Loading video...")
                    } else if let videoURL = selectedVideo {
                        if !isPreviewReady {
                            if let error = previewError {
                                VStack {
                                    Image(systemName: "exclamationmark.triangle")
                                        .font(.largeTitle)
                                        .foregroundColor(.white)
                                    Text(error)
                                        .foregroundColor(.white)
                                        .multilineTextAlignment(.center)
                                        .padding()
                                }
                            } else {
                                ProgressView("Preparing preview...")
                            }
                        } else {
                            ZStack(alignment: .topTrailing) {
                                if let player = player {
                                    VideoPlayer(player: player)
                                        .aspectRatio(aspectRatio, contentMode: .fit)
                                        .cornerRadius(12)
                                        .padding(.horizontal)
                                }
                                
                                if !isCaptionFocused {
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
                            }
                            .fullScreenCover(isPresented: $showingEditor) {
                                EditorView(videoURL: videoURL) { editedVideoURL, metadata in
                                    // Update the selected video with the edited version
                                    selectedVideo = editedVideoURL
                                }
                            }
                        }
                    }
                }
            } else {
                // If no video selected, show the source selection UI
                VideoSourceSelectionView(showingCameraView: $showingCameraView, photoPickerItem: $photoPickerItem)
            }
        }
        .onChange(of: selectedVideo) { oldValue, newValue in
            // Clean up old player when video changes
            if oldValue != newValue {
                print("🎥 [VideoPreviewArea] Video URL changed")
                player?.pause()
                NotificationCenter.default.removeObserver(
                    self,
                    name: .AVPlayerItemDidPlayToEndTime,
                    object: nil
                )
                player = nil
                isPreviewReady = false
                previewError = nil
                
                // Setup new video if available
                if let newURL = newValue {
                    setupVideoPreview(for: newURL)
                }
            }
        }
        .onDisappear {
            print("🎥 [VideoPreviewArea] View disappearing, cleaning up")
            player?.pause()
            NotificationCenter.default.removeObserver(
                self,
                name: .AVPlayerItemDidPlayToEndTime,
                object: nil
            )
            player = nil
        }
    }
}
