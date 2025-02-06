//
//  UploadCompressor.swift
//  Blast
//
//  Created by Silas Pusateri on 2/6/25.
//

import AVFoundation

// Add UploadCompressor class before UploadView
class UploadCompressor {
    static func compressVideo(inputURL: URL, completion: @escaping (Result<URL, Error>) -> Void) {
        let compressionName = UUID().uuidString
        let compressedURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(compressionName).mp4")
        
        // Setup export session with higher quality compression preset
        let asset = AVAsset(url: inputURL)
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1920x1080) else {
            completion(.failure(NSError(domain: "VideoCompressor", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not create export session"])))
            return
        }
        
        // Configure export session
        exportSession.outputURL = compressedURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true
        
        // Start compression
        exportSession.exportAsynchronously {
            DispatchQueue.main.async {
                if let error = exportSession.error {
                    completion(.failure(error))
                } else if let compressedURL = exportSession.outputURL {
                    completion(.success(compressedURL))
                } else {
                    completion(.failure(NSError(domain: "VideoCompressor", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown compression error"])))
                }
            }
        }
    }
}
