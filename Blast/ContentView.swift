//
//  ContentView.swift
//  Blast
//
//  Created by Silas Pusateri on 2/3/25.
//

import SwiftUI
import AVFoundation
import PhotosUI
import FirebaseAuth
import FirebaseStorage
import FirebaseFirestore
import os
import AVKit

struct LoginView: View {
    @EnvironmentObject private var authState: AuthenticationState
    @State private var email = ""
    @State private var password = ""
    @State private var username = ""
    @State private var isSignUp = false
    @State private var errorMessage = ""
    @State private var isLoading = false
    
    // Modify logger initialization to be preview-safe
    #if DEBUG
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.blast", category: "viewCycle")
    #else
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.blast", category: "viewCycle")
    #endif
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Logo/Title
                Text("Blast")
                    .font(.system(size: 40, weight: .bold))
                    .padding(.top, 50)
                
                // Error message
                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding(.horizontal)
                }
                
                // Input fields
                VStack(spacing: 15) {
                    if isSignUp {
                        TextField("Username", text: $username)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    
                    TextField("Email", text: $email)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                    
                    SecureField("Password", text: $password)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                .padding(.horizontal, 32)
                
                // Login/SignUp Button
                Button(action: {
                    isLoading = true
                    errorMessage = ""
                    
                    if isSignUp {
                        // Validate username
                        guard !username.isEmpty else {
                            errorMessage = "Username is required"
                            isLoading = false
                            return
                        }
                        
                        // Sign Up
                        Auth.auth().createUser(withEmail: email, password: password) { result, error in
                            if let error = error {
                                handleAuthResult(error)
                                return
                            }
                            
                            // Store username in Firestore
                            if let user = result?.user {
                                let db = Firestore.firestore()
                                db.collection("users").document(user.uid).setData([
                                    "username": username,
                                    "email": email,
                                    "createdAt": FieldValue.serverTimestamp()
                                ]) { error in
                                    if let error = error {
                                        handleAuthResult(error)
                                        // If storing username fails, delete the created user
                                        try? Auth.auth().currentUser?.delete()
                                    }
                                    isLoading = false
                                }
                            }
                        }
                    } else {
                        // Login
                        Auth.auth().signIn(withEmail: email, password: password) { result, error in
                            handleAuthResult(error)
                        }
                    }
                }) {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Text(isSignUp ? "Sign Up" : "Log In")
                    }
                }
                .frame(width: 200, height: 50)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(25)
                .disabled(isLoading)
                
                // Toggle Login/SignUp
                Button(action: {
                    isSignUp.toggle()
                    errorMessage = ""
                    username = ""  // Clear username when toggling
                }) {
                    Text(isSignUp ? "Already have an account? Log in" : "Don't have an account? Sign up")
                        .foregroundColor(.blue)
                }
                .padding(.top)
                
                Spacer()
            }
            .navigationBarHidden(true)
        }
    }
    
    private func handleAuthResult(_ error: Error?) {
        isLoading = false
        
        if let error = error {
            #if DEBUG
            // In debug mode (including previews), also print to console
            print("🔴 Raw error object: \(String(describing: error))")
            
            if let nsError = error as NSError? {
                print("""
                    🔴 Detailed error information:
                    Domain: \(nsError.domain)
                    Code: \(nsError.code)
                    Description: \(nsError.localizedDescription)
                    User Info: \(nsError.userInfo)
                    """)
            }
            
            if let authError = error as? AuthErrorCode {
                print("""
                    🔴 Firebase Auth error details:
                    Error Code: \(authError.code)
                    Raw Value: \(authError.code.rawValue)
                    Message: \(authError.localizedDescription)
                    """)
            }
            #endif
            
            // Use logger for release builds
            logger.error("🔴 Raw error object: \(String(describing: error))")
            
            if let nsError = error as NSError? {
                logger.error("""
                    🔴 Detailed error information:
                    Domain: \(nsError.domain)
                    Code: \(nsError.code)
                    Description: \(nsError.localizedDescription)
                    User Info: \(nsError.userInfo)
                    """)
            }
            
            errorMessage = error.localizedDescription
        }
        // No need to set isLoggedIn manually anymore as it's handled by AuthenticationState
    }
}

struct ContentView: View {
    @EnvironmentObject private var authState: AuthenticationState
    @StateObject private var videoViewModel = VideoViewModel()
    @State private var showingUploadView = false
    @State private var isRefreshing = false
    @State private var currentVideoIndex = 0
    @State private var showingDeleteConfirmation = false
    @State private var videoToDelete: Video?
    
    var body: some View {
        if !authState.isSignedIn {
            LoginView()
                .edgesIgnoringSafeArea(.all)
        } else {
            MainContentView(
                showingUploadView: $showingUploadView,
                isRefreshing: $isRefreshing,
                currentVideoIndex: $currentVideoIndex,
                showingDeleteConfirmation: $showingDeleteConfirmation,
                videoToDelete: $videoToDelete
            )
            .environmentObject(videoViewModel)
            .edgesIgnoringSafeArea(.all)
        }
    }
}

// New struct to handle main content
struct MainContentView: View {
    @EnvironmentObject var videoViewModel: VideoViewModel
    @EnvironmentObject var authState: AuthenticationState
    @Binding var showingUploadView: Bool
    @Binding var isRefreshing: Bool
    @Binding var currentVideoIndex: Int
    @Binding var showingDeleteConfirmation: Bool
    @Binding var videoToDelete: Video?
    @State private var showingLogoutConfirmation = false
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            VideoScrollView(
                currentVideoIndex: $currentVideoIndex,
                showingDeleteConfirmation: $showingDeleteConfirmation,
                videoToDelete: $videoToDelete,
                isRefreshing: $isRefreshing,
                showingLogoutConfirmation: $showingLogoutConfirmation
            )
            
            TopButtonsView(
                showingUploadView: $showingUploadView,
                isRefreshing: $isRefreshing,
                currentVideoIndex: $currentVideoIndex
            )
        }
        .edgesIgnoringSafeArea(.all)
        .sheet(isPresented: $showingUploadView) {
            // Refresh feed when returning from upload
            Task {
                currentVideoIndex = 0
                await videoViewModel.fetchVideos(isRefresh: true)
                if let firstVideo = videoViewModel.videos.first {
                    VideoPreloadManager.shared.preloadVideo(video: firstVideo)
                }
                if let secondVideo = videoViewModel.videos.dropFirst().first {
                    VideoPreloadManager.shared.preloadVideo(video: secondVideo)
                }
            }
        } content: {
            UploadView()
                .environmentObject(videoViewModel)
        }
        .confirmationDialog(
            "Delete Video",
            isPresented: $showingDeleteConfirmation,
            presenting: videoToDelete
        ) { video in
            Button("Delete", role: .destructive) {
                Task {
                    do {
                        try await videoViewModel.deleteVideo(video)
                    } catch {
                        print("Error deleting video: \(error)")
                    }
                }
            }
        } message: { video in
            Text("Are you sure you want to delete this video? This action cannot be undone.")
        }
        .confirmationDialog(
            "Logout",
            isPresented: $showingLogoutConfirmation
        ) {
            Button("Logout", role: .destructive) {
                do {
                    try Auth.auth().signOut()
                    authState.isSignedIn = false
                } catch {
                    print("Error signing out: \(error)")
                }
            }
        } message: {
            Text("Are you sure you want to logout?")
        }
        .task {
            await videoViewModel.fetchVideos(isRefresh: true)
            if let firstVideo = videoViewModel.videos.first {
                VideoPreloadManager.shared.preloadVideo(video: firstVideo)
            }
            if let secondVideo = videoViewModel.videos.dropFirst().first {
                VideoPreloadManager.shared.preloadVideo(video: secondVideo)
            }
        }
    }
}

// New struct for top buttons
struct TopButtonsView: View {
    @Binding var showingUploadView: Bool
    @Binding var isRefreshing: Bool
    @EnvironmentObject var videoViewModel: VideoViewModel
    @Binding var currentVideoIndex: Int
    
    var body: some View {
        HStack {
            RefreshButton(
                isRefreshing: $isRefreshing,
                currentVideoIndex: $currentVideoIndex
            )
            
            Spacer()
            
            UploadButton(showingUploadView: $showingUploadView)
        }
        .padding(.top, 60)
        .padding(.horizontal, 16)
    }
}

// New struct for refresh button
struct RefreshButton: View {
    @Binding var isRefreshing: Bool
    @EnvironmentObject var videoViewModel: VideoViewModel
    @Binding var currentVideoIndex: Int
    
    var body: some View {
        Button(action: {
            isRefreshing = true
            Task {
                currentVideoIndex = 0
                await videoViewModel.fetchVideos(isRefresh: true)
                isRefreshing = false
            }
        }) {
            Image(systemName: "arrow.clockwise")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(Color.black.opacity(0.5))
                .clipShape(Circle())
        }
    }
}

// New struct for upload button
struct UploadButton: View {
    @Binding var showingUploadView: Bool
    
    var body: some View {
        Button(action: {
            showingUploadView = true
        }) {
            Image(systemName: "plus")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(Color.black.opacity(0.5))
                .clipShape(Circle())
        }
    }
}

// Extension to format dates
extension Date {
    func timeAgo() -> String {
        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: self, to: now)
        
        if let year = components.year, year >= 1 {
            return "\(year)y"
        } else if let month = components.month, month >= 1 {
            return "\(month)mo"
        } else if let day = components.day, day >= 1 {
            return "\(day)d"
        } else if let hour = components.hour, hour >= 1 {
            return "\(hour)h"
        } else if let minute = components.minute, minute >= 1 {
            return "\(minute)m"
        } else {
            return "now"
        }
    }
}

// Preview Providers
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(AuthenticationState())
    }
}

struct LoginView_Previews: PreviewProvider {
    static var previews: some View {
        LoginView()
            .environmentObject(AuthenticationState())
    }
}

#Preview {
    ContentView()
}
