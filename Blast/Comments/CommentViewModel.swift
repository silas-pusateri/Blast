//
//  CommentViewModel.swift
//  Blast
//
//  Created by Silas Pusateri on 2/6/25.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import SwiftUI

// CommentViewModel to manage comment data
@MainActor
class CommentViewModel: ObservableObject {
    @Published var comments: [Comment] = []
    @Published var replies: [String: [Comment]] = [:] // Dictionary to store replies by parent comment ID
    @Published var isLoading = false
    @Published var error: Error?
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
        error = nil
        
        print("Fetching comments for videoId: \(videoId)")  // Debug print
        
        do {
            var query = db.collection("comments")
                .whereField("videoId", isEqualTo: videoId)
                .order(by: "timestamp", descending: true)
                .limit(to: pageSize)
            
            if let lastDocument = lastDocument {
                query = query.start(afterDocument: lastDocument)
            }
            
            let querySnapshot = try await query.getDocuments()
            lastDocument = querySnapshot.documents.last
            
            let newComments = querySnapshot.documents.compactMap { Comment(document: $0) }
            print("Fetched \(newComments.count) comments")
            
            if isRefresh {
                self.comments = newComments
            } else {
                self.comments.append(contentsOf: newComments)
            }
            print("Total comments in array: \(self.comments.count)")
        } catch {
            print("Error fetching comments: \(error)")
            self.error = error
        }
        
        self.isLoading = false
    }
    
    func addComment(to videoId: String, text: String) async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "CommentError", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not logged in"])
        }
        
        print("Adding comment for videoId: \(videoId)")  // Debug print
        
        // Create the comment document reference first
        let commentRef = db.collection("comments").document()
        
        let commentData: [String: Any] = [
            "videoId": videoId,
            "userId": userId,
            "text": text,
            "timestamp": FieldValue.serverTimestamp(),
            "likes": 0
        ]
        
        print("Creating comment with data: \(commentData)")  // Debug print
        
        // Start a batch write
        let batch = db.batch()
        
        // Add comment
        batch.setData(commentData, forDocument: commentRef)
        
        // Update video's comment count
        let videoRef = db.collection("videos").document(videoId)
        batch.updateData(["comments": FieldValue.increment(Int64(1))], forDocument: videoRef)
        
        // Commit the batch
        try await batch.commit()
        print("Comment batch write completed successfully")  // Debug print
        
        // Create a local comment object with the current timestamp
        let comment = Comment(
            id: commentRef.documentID,
            videoId: videoId,
            userId: userId,
            text: text,
            timestamp: Date(),
            likes: 0
        )
        
        // Add to local array at the beginning since we're sorting by timestamp descending
        await MainActor.run {
            self.comments.insert(comment, at: 0)
            print("Added new comment. Total comments: \(self.comments.count)")
        }
        
        // Refresh comments to ensure consistency with server
        print("Refreshing comments after adding new one...")  // Debug print
        await fetchComments(for: videoId, isRefresh: true)
    }
    
    func addReply(to parentCommentId: String, videoId: String, text: String) async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "CommentError", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not logged in"])
        }
        
        // Create the reply in the subcollection
        let replyRef = db.collection("comments")
            .document(parentCommentId)
            .collection("replies")
            .document()
        
        let replyData: [String: Any] = [
            "userId": userId,
            "text": text,
            "timestamp": FieldValue.serverTimestamp(),
            "likes": 0
        ]
        
        // Start a batch write
        let batch = db.batch()
        
        // Add reply to subcollection
        batch.setData(replyData, forDocument: replyRef)
        
        // Update video's comment count
        let videoRef = db.collection("videos").document(videoId)
        batch.updateData(["comments": FieldValue.increment(Int64(1))], forDocument: videoRef)
        
        // Commit the batch
        try await batch.commit()
    }
    
    func toggleLike(for comment: Comment, isReply: Bool = false, parentCommentId: String? = nil) async throws {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let commentPath = isReply ? 
            db.collection("comments").document(parentCommentId!).collection("replies").document(comment.id) :
            db.collection("comments").document(comment.id)
            
        let likeRef = commentPath
            .collection("likes")
            .document(userId)
        
        let likeDoc = try await likeRef.getDocument()
        
        // Start a batch write
        let batch = db.batch()
        
        if likeDoc.exists {
            // Unlike
            batch.deleteDocument(likeRef)
            batch.updateData(["likes": FieldValue.increment(Int64(-1))], forDocument: commentPath)
            
            // Commit the batch
            try await batch.commit()
            
            if isReply {
                if let replyIndex = replies[parentCommentId!]?.firstIndex(where: { $0.id == comment.id }) {
                    replies[parentCommentId!]?[replyIndex].likes -= 1
                }
            } else if let index = comments.firstIndex(where: { $0.id == comment.id }) {
                comments[index].likes -= 1
            }
        } else {
            // Like
            batch.setData(["timestamp": FieldValue.serverTimestamp()], forDocument: likeRef)
            batch.updateData(["likes": FieldValue.increment(Int64(1))], forDocument: commentPath)
            
            // Commit the batch
            try await batch.commit()
            
            if isReply {
                if let replyIndex = replies[parentCommentId!]?.firstIndex(where: { $0.id == comment.id }) {
                    replies[parentCommentId!]?[replyIndex].likes += 1
                }
            } else if let index = comments.firstIndex(where: { $0.id == comment.id }) {
                comments[index].likes += 1
            }
        }
    }
    
    func fetchReplies(for parentCommentId: String) async {
        do {
            let querySnapshot = try await db.collection("comments")
                .document(parentCommentId)
                .collection("replies")
                .order(by: "timestamp", descending: false)
                .getDocuments()
            
            let replies = querySnapshot.documents.compactMap { Comment(document: $0) }
            
            await MainActor.run {
                self.replies[parentCommentId] = replies
            }
        } catch {
            print("Error fetching replies: \(error)")
            self.error = error
        }
    }
}