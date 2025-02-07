//
//  CommentRow.swift
//  Blast
//
//  Created by Silas Pusateri on 2/6/25.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import UIKit

struct CommentRow: View {
    let comment: Comment
    let video: Video
    @EnvironmentObject private var authState: AuthenticationState
    @StateObject private var viewModel = CommentViewModel()
    @State private var showReplies = false
    @State private var replyText = ""
    @State private var isSubmittingReply = false
    @State private var errorMessage: String?
    @State private var isLiked = false
    @State private var username: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Main comment
            HStack(alignment: .top) {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .frame(width: 40, height: 40)
                    .foregroundColor(.gray)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("@\(username)")
                        .font(.system(size: 14, weight: .semibold))
                    Text(comment.text)
                        .font(.system(size: 14))
                    
                    // Comment actions
                    HStack(spacing: 16) {
                        Text(comment.timestamp.timeAgo())
                            .foregroundColor(.gray)
                            .font(.system(size: 12))
                        
                        Button(action: { showReplies.toggle() }) {
                            Text("Reply")
                                .foregroundColor(.gray)
                                .font(.system(size: 12))
                        }
                        .buttonStyle(BorderlessButtonStyle())
                    }
                    .padding(.top, 4)
                }
                
                Spacer()
                
                VStack(spacing: 4) {
                    Button(action: {
                        Task {
                            do {
                                try await viewModel.toggleLike(for: comment)
                                isLiked.toggle()
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                        }
                    }) {
                        Image(systemName: isLiked ? "heart.fill" : "heart")
                            .foregroundColor(isLiked ? .red : .gray)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    
                    Text("\(comment.likes)")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }
            }
            
            // Error message
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
            }
            
            // Replies section
            if showReplies {
                VStack(spacing: 12) {
                    // Reply input
                    HStack(spacing: 8) {
                        Image(systemName: "person.circle.fill")
                            .resizable()
                            .frame(width: 24, height: 24)
                            .foregroundColor(.gray)
                        
                        TextField("Add a reply...", text: $replyText)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .font(.system(size: 12))
                            .disabled(isSubmittingReply)
                        
                        Button(action: {
                            submitReply()
                        }) {
                            if isSubmittingReply {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                                    .scaleEffect(0.6)
                            } else {
                                Text("Reply")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(!replyText.isEmpty ? .blue : .gray)
                            }
                        }
                        .buttonStyle(BorderlessButtonStyle())
                        .disabled(replyText.isEmpty || isSubmittingReply)
                    }
                }
                .padding(.leading, 48)
            }
        }
        .padding(.vertical, 8)
        .task {
            // Check if user has liked this comment
            if let userId = Auth.auth().currentUser?.uid {
                do {
                    let likeDoc = try await Firestore.firestore()
                        .collection("comments")
                        .document(comment.id)
                        .collection("likes")
                        .document(userId)
                        .getDocument()
                    
                    isLiked = likeDoc.exists
                } catch {
                    print("Error checking like status: \(error)")
                }
            }
            
            // Fetch username
            if let cachedUsername = UsernameCache.shared.getUsername(for: comment.userId) {
                username = cachedUsername
            } else {
                let db = Firestore.firestore()
                do {
                    let userDoc = try await db.collection("users").document(comment.userId).getDocument()
                    if let data = userDoc.data(),
                       let fetchedUsername = data["username"] as? String {
                        UsernameCache.shared.setUsername(fetchedUsername, for: comment.userId)
                        username = fetchedUsername
                    } else {
                        username = "User"
                    }
                } catch {
                    print("Error fetching username: \(error)")
                    username = "User"
                }
            }
        }
    }
    
    private func submitReply() {
        isSubmittingReply = true
        errorMessage = nil
        
        Task {
            do {
                try await viewModel.addReply(to: comment.id, videoId: video.id, text: replyText)
                replyText = ""
                // Hide keyboard
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                             to: nil, from: nil, for: nil)
            } catch {
                errorMessage = error.localizedDescription
            }
            isSubmittingReply = false
        }
    }
}
