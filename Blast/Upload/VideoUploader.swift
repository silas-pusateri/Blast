import FirebaseStorage
import FirebaseFirestore
import Foundation

class VideoUploader {
    static let shared = VideoUploader()
    private let storage = Storage.storage()
    
    private init() {}
    
    func uploadVideo(from localURL: URL, to path: String) async throws -> String {
        // First compress the video
        return try await withCheckedThrowingContinuation { continuation in
            UploadCompressor.compressVideo(inputURL: localURL) { result in
                switch result {
                case .success(let compressedURL):
                    // Upload the compressed video
                    let storageRef = self.storage.reference().child(path)
                    
                    let metadata = StorageMetadata()
                    metadata.contentType = "video/mp4"
                    
                    storageRef.putFile(from: compressedURL, metadata: metadata) { metadata, error in
                        if let error = error {
                            continuation.resume(throwing: error)
                            return
                        }
                        
                        // Get the download URL
                        storageRef.downloadURL { url, error in
                            if let error = error {
                                continuation.resume(throwing: error)
                                return
                            }
                            
                            guard let downloadURL = url else {
                                continuation.resume(throwing: NSError(domain: "VideoUploader", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to get download URL"]))
                                return
                            }
                            
                            // Clean up the compressed file
                            try? FileManager.default.removeItem(at: compressedURL)
                            
                            continuation.resume(returning: downloadURL.absoluteString)
                        }
                    }
                    
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func deleteVideo(at url: String) async throws {
        guard let videoURL = URL(string: url),
              videoURL.host?.contains("firebasestorage.googleapis.com") == true else {
            return // Not a Firebase Storage URL, nothing to delete
        }
        
        let storageRef = storage.reference(forURL: url)
        try await storageRef.delete()
    }
} 