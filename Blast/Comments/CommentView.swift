//
//  CommentView.swift
//  Blast
//
//  Created by Silas Pusateri on 2/6/25.
//

import SwiftUI
import FirebaseAuth

struct CommentView: View {
    @Environment(\.dismiss) var dismiss
    let video: Video
    @StateObject private var viewModel = CommentViewModel()
    @State private var newComment = ""
    @State private var errorMessage: String?
    @State private var isSubmitting = false
    
    var body: some View {
        NavigationView {
            VStack {
                if viewModel.isLoading && viewModel.comments.isEmpty {
                    ProgressView()
                        .frame(maxHeight: .infinity)
                } else {
                    List {
                        ForEach(viewModel.comments) { comment in
                            CommentRow(comment: comment, video: video)
                        }
                        
                        if !viewModel.comments.isEmpty && viewModel.isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                    }
                    .listStyle(PlainListStyle())
                    .refreshable {
                        await viewModel.fetchComments(for: video.id, isRefresh: true)
                    }
                }
                
                // Error message
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding(.horizontal)
                }
                
                // Comment input area
                HStack(spacing: 12) {
                    Image(systemName: "person.circle.fill")
                        .resizable()
                        .frame(width: 32, height: 32)
                        .foregroundColor(.gray)
                    
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
            await viewModel.fetchComments(for: video.id)
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

