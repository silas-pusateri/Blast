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
            "videoId": videoId,
            "userId": userId,
            "timestamp": FieldValue.serverTimestamp(),
            "status": Change.ChangeStatus.open.rawValue,
            "description": description,
            "editUrl": editUrl as Any,
            "diffMetadata": diffMetadata as Any
        ]
        
        try await db.collection("changes").addDocument(data: data)
    }
    
    func fetchChanges(videoId: String) async throws {
        let snapshot = try await db.collection("changes")
            .whereField("videoId", isEqualTo: videoId)
            .order(by: "timestamp", descending: true)
            .getDocuments()
        
        changes = snapshot.documents.compactMap { Change(document: $0) }
    }
    
    func acceptChange(_ change: Change) async throws {
        // First update the change status
        try await updateChangeStatus(change, newStatus: .accepted)
        
        // Get the current video data
        let videoRef = db.collection("videos").document(change.videoId)
        let videoDoc = try await videoRef.getDocument()
        guard let videoData = videoDoc.data() else {
            throw NSError(domain: "ChangesViewModel", code: 2, userInfo: [NSLocalizedDescriptionKey: "Original video not found"])
        }
        
        // If there's an edited video URL, create a new video post
        if let editUrl = change.editUrl {
            // Create new video document with updated URL and version info
            let newVideoData: [String: Any] = [
                "userId": videoData["userId"] as? String ?? "",
                "caption": videoData["caption"] as? String ?? "",
                "videoUrl": editUrl,
                "timestamp": FieldValue.serverTimestamp(),
                "likes": 0,
                "comments": 0,
                "previousVersionId": change.videoId,
                "changeDescription": change.description
            ]
            
            // Start a batch write
            let batch = db.batch()
            
            // Add new video document
            let newVideoRef = db.collection("videos").document()
            batch.setData(newVideoData, forDocument: newVideoRef)
            
            // Delete old video document
            batch.deleteDocument(videoRef)
            
            // Commit the batch
            try await batch.commit()
            
            // Clean up the old video file
            if let oldUrl = videoData["videoUrl"] as? String,
               let storagePath = URL(string: oldUrl)?.path.components(separatedBy: "o/").last?.removingPercentEncoding {
                let storage = Storage.storage()
                let oldRef = storage.reference().child(storagePath)
                try await oldRef.delete()
            }
            
            // Refresh the video feed
            await videoViewModel.fetchVideos(isRefresh: true)
        }
        
        // Refresh changes
        try await fetchChanges(videoId: change.videoId)
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
        let changeRef = db.collection("changes").document(change.id)
        try await changeRef.updateData([
            "status": newStatus.rawValue
        ])
    }
} 