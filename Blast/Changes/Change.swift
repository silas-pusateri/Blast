import Foundation
import FirebaseFirestore

struct Change: Identifiable {
    let id: String
    let videoId: String
    let userId: String
    let timestamp: Date
    let status: ChangeStatus
    let description: String
    let editUrl: String?
    let diffMetadata: [String: Any]?
    
    enum ChangeStatus: String, Codable {
        case open
        case accepted
        case rejected
    }
    
    init(id: String, videoId: String, userId: String, timestamp: Date, status: ChangeStatus, description: String, editUrl: String? = nil, diffMetadata: [String: Any]? = nil) {
        self.id = id
        self.videoId = videoId
        self.userId = userId
        self.timestamp = timestamp
        self.status = status
        self.description = description
        self.editUrl = editUrl
        self.diffMetadata = diffMetadata
    }
    
    init?(document: DocumentSnapshot) {
        guard 
            let data = document.data(),
            let videoId = data["videoId"] as? String,
            let userId = data["userId"] as? String,
            let timestamp = (data["timestamp"] as? Timestamp)?.dateValue(),
            let statusRaw = data["status"] as? String,
            let status = ChangeStatus(rawValue: statusRaw),
            let description = data["description"] as? String
        else {
            return nil
        }
        
        self.id = document.documentID
        self.videoId = videoId
        self.userId = userId
        self.timestamp = timestamp
        self.status = status
        self.description = description
        self.editUrl = data["editUrl"] as? String
        self.diffMetadata = data["diffMetadata"] as? [String: Any]
    }
} 