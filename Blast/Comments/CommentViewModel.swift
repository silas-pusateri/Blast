//
//  CommentViewModel.swift
//  Blast
//
//  Created by Silas Pusateri on 2/6/25.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

// CommentViewModel to manage comment data
@MainActor
class CommentViewModel: ObservableObject {
    @Published var comments: [Comment] = []
    @Published var isLoading = false
    private var lastDocument: QueryDocumentSnapshot?
    private let pageSize = 20
    private let db = Firestore.firestore()
    
    func fetchComments(for videoId: String, isRefresh: Bool = false) async {
        if isRefresh {
            comments = []
            lastDocument = nil
        }
        
        guard !isLoading else { return }
        isLoading = true
        
        do {
            var query = db.collection("comments")
                .whereField("videoId", isEqualTo: videoId)
                .whereField("parentCommentId", isEqualTo: NSNull())
                .order(by: "timestamp", descending: true)
                .limit(to: pageSize)
            
            if let lastDocument = lastDocument {
                query = query.start(afterDocument: lastDocument)
            }
            
            let querySnapshot = try await query.getDocuments()
            lastDocument = querySnapshot.documents.last
            
            let newComments = querySnapshot.documents.compactMap { Comment(document: $0) }
            
            await MainActor.run {
                if isRefresh {
                    self.comments = newComments
                } else {
                    self.comments.append(contentsOf: newComments)
                }
                self.isLoading = false
            }
        } catch {
            print("Error fetching comments: \(error)")
            await MainActor.run {
                self.isLoading = false
            }
        }
    }
    
    func addComment(to videoId: String, text: String) async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "CommentError", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not logged in"])
        }
        
        let comment = Comment(videoId: videoId, userId: userId, text: text)
        
        // Create dictionary on MainActor
        let commentData: [String: Any] = [
            "videoId": comment.videoId,
            "userId": comment.userId,
            "text": comment.text,
            "timestamp": FieldValue.serverTimestamp(),
            "likes": comment.likes
        ]
        
        // Add comment to Firestore
        try await db.collection("comments").document(comment.id).setData(commentData)
        
        // Update video's comment count
        let videoRef = db.collection("videos").document(videoId)
        try await videoRef.updateData([
            "comments": FieldValue.increment(Int64(1))
        ])
        
        // Add comment to local array
        comments.insert(comment, at: 0)
    }
    
    func addReply(to parentCommentId: String, videoId: String, text: String) async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "CommentError", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not logged in"])
        }
        
        let reply = Comment(
            videoId: videoId,
            userId: userId,
            text: text,
            parentCommentId: parentCommentId
        )
        
        // Create dictionary on MainActor
        let replyData: [String: Any] = [
            "videoId": reply.videoId,
            "userId": reply.userId,
            "text": reply.text,
            "timestamp": FieldValue.serverTimestamp(),
            "likes": reply.likes,
            "parentCommentId": parentCommentId
        ]
        
        // Add reply to Firestore
        try await db.collection("comments").document(reply.id).setData(replyData)
        
        // Update video's comment count
        let videoRef = db.collection("videos").document(videoId)
        try await videoRef.updateData([
            "comments": FieldValue.increment(Int64(1))
        ])
    }
    
    func toggleLike(for comment: Comment) async throws {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let likeRef = db.collection("comments")
            .document(comment.id)
            .collection("likes")
            .document(userId)
        
        let commentRef = db.collection("comments").document(comment.id)
        let likeDoc = try await likeRef.getDocument()
        
        if likeDoc.exists {
            // Unlike
            try await likeRef.delete()
            try await commentRef.updateData([
                "likes": FieldValue.increment(Int64(-1))
            ])
            
            if let index = comments.firstIndex(where: { $0.id == comment.id }) {
                comments[index].likes -= 1
            }
        } else {
            // Like
            try await likeRef.setData(["timestamp": FieldValue.serverTimestamp()])
            try await commentRef.updateData([
                "likes": FieldValue.increment(Int64(1))
            ])
            
            if let index = comments.firstIndex(where: { $0.id == comment.id }) {
                comments[index].likes += 1
            }
        }
    }
}