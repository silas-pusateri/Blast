import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseStorage

@MainActor
class ChangesViewModel: ObservableObject {
    @Published var changes: [Change] = []
    private let db = Firestore.firestore()
    private let videoViewModel: VideoViewModel
    
    init(videoViewModel: VideoViewModel) {
        self.videoViewModel = videoViewModel
    }
    
    func createChange(videoId: String, description: String, editUrl: String? = nil, diffMetadata: [String: Any]? = nil) async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "ChangesViewModel", code: 1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        let data: [String: Any] = [
            "userId": userId,
            "timestamp": FieldValue.serverTimestamp(),
            "status": Change.ChangeStatus.open.rawValue,
            "description": description,
            "editUrl": editUrl as Any,
            "diffMetadata": diffMetadata as Any
        ]
        
        // Create the change in the video's changes subcollection
        try await db.collection("videos")
            .document(videoId)
            .collection("changes")
            .addDocument(data: data)
    }
    
    func fetchChanges(videoId: String) async throws {
        let snapshot = try await db.collection("videos")
            .document(videoId)
            .collection("changes")
            .order(by: "timestamp", descending: true)
            .getDocuments()
        
        changes = snapshot.documents.compactMap { Change(document: $0, videoId: videoId) }
    }
    
    func acceptChange(_ change: Change) async throws {
        print("📹 Starting to accept change with ID: \(change.id)")
        
        // First update the change status
        try await updateChangeStatus(change, newStatus: .accepted)
        
        // Then update the video with the new URL if available
        if let editUrl = change.editUrl {
            print("📹 Processing edit URL: \(editUrl)")
            
            // Download the edited video data asynchronously
            guard let url = URL(string: editUrl) else {
                throw NSError(domain: "ChangesViewModel", code: 2,
                            userInfo: [NSLocalizedDescriptionKey: "Invalid edit URL"])
            }
            
            print("📹 Starting async download of edited video")
            let (data, _) = try await URLSession.shared.data(from: url)
            print("📹 Successfully downloaded edited video data")
            
            // Generate a new unique path for the accepted edit
            let timestamp = Int(Date().timeIntervalSince1970)
            let filename = "\(UUID().uuidString)_accepted_\(timestamp).mp4"
            let storagePath = "videos/\(filename)"
            print("📹 Generated new storage path: \(storagePath)")
            
            do {
                // Upload the edited video to Firebase Storage
                let storage = Storage.storage()
                let storageRef = storage.reference().child(storagePath)
                
                // Upload the data
                let metadata = StorageMetadata()
                metadata.contentType = "video/mp4"
                try await storageRef.putData(data, metadata: metadata)
                print("📹 Successfully uploaded edited video to storage")
                
                // Add a longer initial delay to ensure the file is fully processed
                try await Task.sleep(nanoseconds: 2_000_000_000) // 2 second delay
                
                // Try to get the download URL with retries and exponential backoff
                var downloadURL: URL?
                var retryCount = 0
                let maxRetries = 5
                
                while downloadURL == nil && retryCount < maxRetries {
                    do {
                        downloadURL = try await storageRef.downloadURL()
                        print("📹 Got download URL on attempt \(retryCount + 1): \(downloadURL?.absoluteString ?? "nil")")
                        break
                    } catch {
                        retryCount += 1
                        if retryCount < maxRetries {
                            print("📹 Retry \(retryCount)/\(maxRetries) getting download URL: \(error.localizedDescription)")
                            // Exponential backoff: 2, 4, 8, 16 seconds
                            let delaySeconds = UInt64(pow(2.0, Double(retryCount))) * 1_000_000_000
                            try await Task.sleep(nanoseconds: delaySeconds)
                        } else {
                            throw error
                        }
                    }
                }
                
                guard let newDownloadURL = downloadURL else {
                    throw NSError(domain: "ChangesViewModel", code: 3,
                                userInfo: [NSLocalizedDescriptionKey: "Failed to get download URL after \(maxRetries) attempts"])
                }
                
                // Get the original video data
                let firestoreRef = db.collection("videos").document(change.videoId)
                let videoDoc = try await firestoreRef.getDocument()
                guard let videoData = videoDoc.data() else {
                    throw NSError(domain: "ChangesViewModel", code: 4,
                                userInfo: [NSLocalizedDescriptionKey: "Failed to get original video data"])
                }
                
                // Create a new video document with the edited URL
                let newVideoData: [String: Any] = [
                    "videoUrl": newDownloadURL.absoluteString,
                    "caption": videoData["caption"] as? String ?? "",
                    "userId": videoData["userId"] as? String ?? "",
                    "likes": 0,
                    "comments": 0,
                    "timestamp": FieldValue.serverTimestamp(),
                    "isEdited": true,
                    "originalVideoId": change.videoId
                ]
                
                // Add the new video document
                let newDocRef = try await db.collection("videos").addDocument(data: newVideoData)
                print("📹 Created new video entry with edited URL: \(newDocRef.documentID)")
                
                // Wait a moment for the server timestamp to be set
                try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
                
                // Refresh the video list to show the new entry
                await videoViewModel.fetchVideos(isRefresh: true)
            } catch {
                print("📹 Error during storage operations: \(error.localizedDescription)")
                throw error
            }
        }
        
        // Refresh changes
        try await fetchChanges(videoId: change.videoId)
        print("📹 Completed accepting change")
    }
    
    func rejectChange(_ change: Change) async throws {
        try await updateChangeStatus(change, newStatus: .rejected)
        
        // If there's an edited video URL, clean it up
        if let editUrl = change.editUrl,
           let storagePath = URL(string: editUrl)?.path.components(separatedBy: "o/").last?.removingPercentEncoding {
            let storage = Storage.storage()
            let editedVideoRef = storage.reference().child(storagePath)
            try await editedVideoRef.delete()
        }
        
        // Refresh changes
        try await fetchChanges(videoId: change.videoId)
    }
    
    private func updateChangeStatus(_ change: Change, newStatus: Change.ChangeStatus) async throws {
        let changeRef = db.collection("videos")
            .document(change.videoId)
            .collection("changes")
            .document(change.id)
        
        try await changeRef.updateData([
            "status": newStatus.rawValue
        ])
    }
} 