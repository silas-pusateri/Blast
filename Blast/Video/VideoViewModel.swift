//
//  VideoViewModel.swift
//  Blast
//
//  Created by Silas Pusateri on 2/6/25.
//

import Foundation
import Combine
import FirebaseFirestore
import FirebaseStorage

// Add this class to manage video data
class VideoViewModel: ObservableObject {
    @Published var videos: [Video] = []
    @Published var isLoading = false
    @Published var hasMoreVideos = true
    private var lastDocument: DocumentSnapshot?
    private let pageSize = 5
    
    @MainActor
    func fetchVideos(isRefresh: Bool = false) async {
        if isRefresh {
            // Reset pagination state on refresh
            videos = []
            lastDocument = nil
            hasMoreVideos = true
            // Clear all preloaded videos on refresh
            VideoPreloadManager.shared.clearAllPreloadedVideos()
        }
        
        // Don't fetch if we're already loading or there are no more videos
        guard !isLoading && hasMoreVideos else { return }
        
        isLoading = true
        
        // Fetch videos from Firestore
        let db = Firestore.firestore()
        do {
            var query = db.collection("videos")
                .order(by: "timestamp", descending: true)
                .limit(to: pageSize)
            
            // If we have a last document and this isn't a refresh, start after it
            if let lastDocument = lastDocument, !isRefresh {
                query = query.start(afterDocument: lastDocument)
            }
            
            let querySnapshot = try await query.getDocuments()
            
            // Update pagination state
            lastDocument = querySnapshot.documents.last
            hasMoreVideos = !querySnapshot.documents.isEmpty && querySnapshot.documents.count == pageSize
            
            // Parse and append new videos
            let newVideos = querySnapshot.documents.compactMap { document -> Video? in
                let data = document.data()
                return Video(
                    id: document.documentID,
                    url: data["videoUrl"] as? String ?? "",
                    caption: data["caption"] as? String ?? "",
                    userId: data["userId"] as? String ?? "",
                    likes: data["likes"] as? Int ?? 0,
                    comments: data["comments"] as? Int ?? 0
                )
            }
            
            // Append new videos to existing list
            if isRefresh {
                videos = newVideos
            } else {
                videos.append(contentsOf: newVideos)
            }
            
            // Preload first two videos if this is a refresh or we're at the start
            if isRefresh || videos.count <= pageSize {
                if let firstVideo = videos.first {
                    VideoPreloadManager.shared.preloadVideo(video: firstVideo)
                }
                if videos.count > 1 {
                    VideoPreloadManager.shared.preloadVideo(video: videos[1])
                }
            }
            
            isLoading = false
        } catch {
            print("Error fetching videos: \(error)")
            isLoading = false
        }
    }
    
    @MainActor
    func deleteVideo(_ video: Video) async throws {
        let db = Firestore.firestore()
        let storage = Storage.storage()
        
        // Delete video file from Storage
        if let videoUrl = URL(string: video.url),
           let storagePath = videoUrl.path.components(separatedBy: "o/").last?.removingPercentEncoding {
            let storageRef = storage.reference().child(storagePath)
            try await storageRef.delete()
        }
        
        // Delete video document from Firestore
        try await db.collection("videos").document(video.id).delete()
        
        // Remove video from local array
        if let index = videos.firstIndex(where: { $0.id == video.id }) {
            videos.remove(at: index)
        }
    }
}
