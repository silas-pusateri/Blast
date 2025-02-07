//
//  VideoSourceSelectionView.swift
//  Blast
//
//  Created by Silas Pusateri on 2/6/25.
//

import SwiftUI
import PhotosUI

/// Separate small subview to choose source (camera/gallery).
struct VideoSourceSelectionView: View {
    @Binding var showingCameraView: Bool
    @Binding var photoPickerItem: PhotosPickerItem?
    
    var body: some View {
        GeometryReader { geometry in
            VStack {
                // Position buttons in upper third
                HStack(spacing: 20) {
                    // Camera Button
                    Button(action: {
                        showingCameraView = true
                    }) {
                        VStack(spacing: 12) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 32))
                            Text("Record")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .frame(width: 140, height: 140)
                        .background(Color.red)
                        .cornerRadius(16)
                    }
                    
                    // Gallery Button
                    PhotosPicker(
                        selection: $photoPickerItem,
                        matching: .videos,
                        photoLibrary: .shared()
                    ) {
                        VStack(spacing: 12) {
                            Image(systemName: "photo.fill")
                                .font(.system(size: 32))
                            Text("Gallery")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .frame(width: 140, height: 140)
                        .background(Color.black)
                        .cornerRadius(16)
                    }
                }
                .padding(.top, geometry.size.height * 0.15)
                
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}