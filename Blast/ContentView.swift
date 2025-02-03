//
//  ContentView.swift
//  Blast
//
//  Created by Silas Pusateri on 2/3/25.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        GeometryReader { geometry in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(0..<5) { index in
                        VideoView(index: index)
                            .frame(width: geometry.size.width,
                                   height: geometry.size.height)
                    }
                }
            }
            .scrollTargetBehavior(.paging)
        }
        .edgesIgnoringSafeArea(.all)
    }
}

struct VideoView: View {
    let index: Int
    @State private var isLiked = false
    @State private var likeCount = Int.random(in: 100...10000)
    @State private var commentCount = Int.random(in: 10...1000)
    @State private var shareCount = Int.random(in: 10...500)
    
    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black // Placeholder for video
            
            // Bottom content overlay
            HStack(alignment: .bottom) {
                // Left side - Username and description
                VStack(alignment: .leading, spacing: 8) {
                    Text("@creator\(index)")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("This is an awesome video description! #trending #viral #fun")
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.leading)
                }
                .padding(.leading, 20)
                .padding(.bottom, 50)
                
                Spacer()
                
                // Right side - Interaction buttons
                VStack(spacing: 20) {
                    // Profile Button
                    Button(action: {}) {
                        Image(systemName: "person.circle.fill")
                            .resizable()
                            .frame(width: 50, height: 50)
                            .foregroundColor(.white)
                    }
                    
                    // Like Button
                    VStack(spacing: 5) {
                        Button(action: {
                            isLiked.toggle()
                            likeCount += isLiked ? 1 : -1
                        }) {
                            Image(systemName: isLiked ? "heart.fill" : "heart")
                                .resizable()
                                .frame(width: 35, height: 35)
                                .foregroundColor(isLiked ? .red : .white)
                        }
                        Text("\(likeCount)")
                            .foregroundColor(.white)
                            .font(.caption)
                    }
                    
                    // Comment Button
                    VStack(spacing: 5) {
                        Button(action: {}) {
                            Image(systemName: "bubble.right")
                                .resizable()
                                .frame(width: 35, height: 35)
                                .foregroundColor(.white)
                        }
                        Text("\(commentCount)")
                            .foregroundColor(.white)
                            .font(.caption)
                    }
                    
                    // Share Button
                    VStack(spacing: 5) {
                        Button(action: {}) {
                            Image(systemName: "arrowshape.turn.up.right")
                                .resizable()
                                .frame(width: 35, height: 35)
                                .foregroundColor(.white)
                        }
                        Text("\(shareCount)")
                            .foregroundColor(.white)
                            .font(.caption)
                    }
                }
                .padding(.trailing, 20)
                .padding(.bottom, 50)
            }
        }
    }
}

#Preview {
    ContentView()
}
