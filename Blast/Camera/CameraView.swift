//
//  CameraView.swift
//  Blast
//
//  Created by Silas Pusateri on 2/6/25.
//

import SwiftUI
import AVFoundation

struct CameraView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var selectedVideo: URL?
    @StateObject private var cameraManager = CameraManager()
    @State private var isRecording = false
    
    var body: some View {
        Group {
            if cameraManager.isSimulator {
                // Simulator view
                VStack {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 40))
                        .padding()
                    Text("Camera not available in Simulator")
                        .font(.headline)
                    Text("Please test this feature on a physical device")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .padding()
                    Button("Close") {
                        dismiss()
                    }
                    .padding()
                }
            } else {
                // Real device camera view
                ZStack {
                    CameraPreviewView(session: cameraManager.session)
                        .ignoresSafeArea()
                    
                    // Camera controls
                    VStack {
                        Spacer()
                        
                        HStack(spacing: 30) {
                            // Flip camera button
                            Button(action: {
                                cameraManager.switchCamera()
                            }) {
                                Image(systemName: "camera.rotate.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(.white)
                                    .frame(width: 60, height: 60)
                                    .background(Color.black.opacity(0.5))
                                    .clipShape(Circle())
                            }
                            
                            // Record button
                            Button(action: {
                                if isRecording {
                                    cameraManager.stopRecording()
                                } else {
                                    cameraManager.startRecording { url in
                                        selectedVideo = url
                                        dismiss()
                                    }
                                }
                                isRecording.toggle()
                            }) {
                                Circle()
                                    .stroke(Color.white, lineWidth: 4)
                                    .frame(width: 80, height: 80)
                                    .overlay(
                                        Circle()
                                            .fill(isRecording ? Color.red : Color.white)
                                            .frame(width: 70, height: 70)
                                    )
                            }
                            
                            // Close button
                            Button(action: {
                                dismiss()
                            }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 24))
                                    .foregroundColor(.white)
                                    .frame(width: 60, height: 60)
                                    .background(Color.black.opacity(0.5))
                                    .clipShape(Circle())
                            }
                        }
                        .padding(.bottom, 50)
                    }
                }
            }
        }
        .onAppear {
            cameraManager.checkPermissions()
            cameraManager.setupSession()
        }
    }
}