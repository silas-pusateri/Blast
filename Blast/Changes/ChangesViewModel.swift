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
        
        // Then update the video with the new URL if available
        if let editUrl = change.editUrl {
            // Update the video URL in both Firestore and the local view model
            try await videoViewModel.updateVideoURL(videoId: change.videoId, newURL: editUrl)
            
            // Get the current video data to find the old URL
            let videoRef = db.collection("videos").document(change.videoId)
            let videoDoc = try await videoRef.getDocument()
            
            // Clean up the old video file if it exists
            if let oldUrl = videoDoc.data()?["videoUrl"] as? String,
               let storagePath = URL(string: oldUrl)?.path.components(separatedBy: "o/").last?.removingPercentEncoding {
                let storage = Storage.storage()
                let oldRef = storage.reference().child(storagePath)
                try await oldRef.delete()
            }
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