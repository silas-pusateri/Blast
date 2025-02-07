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
                    }
                }
            } else {
                // If no video selected, show the source selection UI
                VideoSourceSelectionView(showingCameraView: $showingCameraView, photoPickerItem: $photoPickerItem)
            }
        }
    }
}
