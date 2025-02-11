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
    
    var body: some View {
        Group {
            if isLoadingVideo || selectedVideo != nil {
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
                                    let newPlayer = AVPlayer(url: videoURL)
                                    player = newPlayer
                                    
                                    // Setup video looping
                                    NotificationCenter.default.addObserver(
                                        forName: .AVPlayerItemDidPlayToEndTime,
                                        object: newPlayer.currentItem,
                                        queue: .main) { _ in
                                            newPlayer.seek(to: .zero)
                                            newPlayer.play()
                                        }
                                    
                                    // Start playing
                                    newPlayer.play()
                                }
                                .onDisappear {
                                    // Cleanup player and observers when view disappears
                                    player?.pause()
                                    NotificationCenter.default.removeObserver(
                                        self,
                                        name: .AVPlayerItemDidPlayToEndTime,
                                        object: nil
                                    )
                                    player = nil
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
            } else {
                // If no video selected, show the source selection UI
                VideoSourceSelectionView(showingCameraView: $showingCameraView, photoPickerItem: $photoPickerItem)
            }
        }
        .onChange(of: selectedVideo) { oldValue, newValue in
            // Clean up old player when video changes
            if oldValue != newValue {
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
}
