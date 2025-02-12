//
//  CommentView.swift
//  Blast
//
//  Created by Silas Pusateri on 2/6/25.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct CommentView: View {
    @Environment(\.dismiss) var dismiss
    let video: Video
    @StateObject private var viewModel = CommentViewModel()
    @State private var newComment = ""
    @State private var errorMessage: String?
    @State private var isSubmitting = false
    @State private var currentUsername: String = ""
    
    var body: some View {
        NavigationView {
            VStack {
                if viewModel.isLoading && viewModel.comments.isEmpty {
                    ProgressView()
                        .frame(maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            if !viewModel.comments.isEmpty {
                                ForEach(viewModel.comments) { comment in
                                    CommentRow(comment: comment, video: video)
                                        .environmentObject(viewModel)
                                        .padding(.horizontal)
                                    
                                    Divider()
                                }
                            }
                            
                            if viewModel.isLoading {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                                    .padding()
                            }
                            
                            if viewModel.comments.isEmpty && !viewModel.isLoading {
                                VStack(spacing: 12) {
                                    Image(systemName: "bubble.right")
                                        .font(.system(size: 40))
                                        .foregroundColor(.gray)
                                    Text("No comments yet")
                                        .font(.headline)
                                        .foregroundColor(.gray)
                                    Text("Be the first to comment!")
                                        .font(.subheadline)
                                        .foregroundColor(.gray)
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .padding(.top, 100)
                            }
                        }
                    }
                    .refreshable {
                        print("Refreshing comments...") // Debug print
                        await viewModel.fetchComments(for: video.id, isRefresh: true)
                    }
                }
                
                // Error message
                if let error = viewModel.error {
                    Text(error.localizedDescription)
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding(.horizontal)
                }
                
                // Comment input area
                VStack(spacing: 8) {
                    if let errorMessage = errorMessage {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.caption)
                            .padding(.horizontal)
                    }
                    
                    HStack(spacing: 12) {
                        VStack(alignment: .center, spacing: 2) {
                            Image(systemName: "person.circle.fill")
                                .resizable()
                                .frame(width: 32, height: 32)
                                .foregroundColor(.gray)
                            Text("@\(currentUsername)")
                                .font(.system(size: 10))
                                .foregroundColor(.gray)
                        }
                        .frame(width: 32)
                        
                        TextField("Add a comment...", text: $newComment)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .disabled(isSubmitting)
                        
                        Button(action: {
                            submitComment()
                        }) {
                            if isSubmitting {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                                    .scaleEffect(0.8)
                            } else {
                                Text("Post")
                                    .fontWeight(.semibold)
                                    .foregroundColor(!newComment.isEmpty ? .blue : .gray)
                            }
                        }
                        .disabled(newComment.isEmpty || isSubmitting)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(UIColor.systemBackground))
                .overlay(
                    Rectangle()
                        .frame(height: 0.5)
                        .foregroundColor(Color(UIColor.systemGray3)),
                    alignment: .top
                )
            }
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            print("Initial comment fetch...") // Debug print
            await viewModel.fetchComments(for: video.id)
            
            // Fetch current user's username
            if let userId = Auth.auth().currentUser?.uid {
                if let cachedUsername = UsernameCache.shared.getUsername(for: userId) {
                    currentUsername = cachedUsername
                } else {
                    let db = Firestore.firestore()
                    do {
                        let userDoc = try await db.collection("users").document(userId).getDocument()
                        if let data = userDoc.data(),
                           let username = data["username"] as? String {
                            UsernameCache.shared.setUsername(username, for: userId)
                            currentUsername = username
                        } else {
                            currentUsername = "User"
                        }
                    } catch {
                        print("Error fetching current username: \(error)")
                        currentUsername = "User"
                    }
                }
            }
        }
    }
    
    private func submitComment() {
        isSubmitting = true
        errorMessage = nil
        
        Task {
            do {
                try await viewModel.addComment(to: video.id, text: newComment)
                newComment = ""
                // Hide keyboard
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                             to: nil, from: nil, for: nil)
            } catch {
                errorMessage = error.localizedDescription
            }
            isSubmitting = false
        }
    }
}

