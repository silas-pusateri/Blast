import SwiftUI
import PhotosUI
import FirebaseFirestore

// For Firestore video data
struct VideoData: Codable {
    let userId: String
    let caption: String
    let videoUrl: String
    let likes: Int
    let comments: Int
    var timestamp: Timestamp
    var id: String
    
    enum CodingKeys: String, CodingKey {
        case userId, caption, videoUrl, likes, comments, timestamp
        case id
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userId = try container.decode(String.self, forKey: .userId)
        caption = try container.decode(String.self, forKey: .caption)
        videoUrl = try container.decode(String.self, forKey: .videoUrl)
        likes = try container.decode(Int.self, forKey: .likes)
        comments = try container.decode(Int.self, forKey: .comments)
        timestamp = try container.decode(Timestamp.self, forKey: .timestamp)
        
        // Extract document ID from reference path
        let documentPath = decoder.userInfo[.documentPath] as? String ?? ""
        id = documentPath.components(separatedBy: "/").last ?? ""
    }
}

// Extension to provide document path in decoder userInfo
extension CodingUserInfoKey {
    static let documentPath = CodingUserInfoKey(rawValue: "documentPath")!
}

// For video transfer
struct VideoTransferData: Transferable {
    let data: Data
    
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .movie) { data in
            VideoTransferData(data: data)
        }
    }
} 