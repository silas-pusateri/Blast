import SwiftUI
import AVKit

struct EditorView: View {
    @Environment(\.dismiss) var dismiss
    let videoURL: URL
    let onSave: (URL) -> Void
    @State private var player: AVPlayer?
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var isPlaying = false
    @State private var trimStartTime: Double = 0
    @State private var trimEndTime: Double = 0
    @State private var isSaving = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationView {
            VStack {
                // Video preview
                if let player = player {
                    VideoPlayer(player: player)
                        .aspectRatio(9/16, contentMode: .fit)
                        .cornerRadius(12)
                        .padding()
                }
                
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding(.horizontal)
                }
                
                // Trim controls
                VStack(spacing: 20) {
                    HStack {
                        Text("Start: \(formatTime(trimStartTime))")
                        Spacer()
                        Text("End: \(formatTime(trimEndTime))")
                    }
                    .padding(.horizontal)
                    
                    // Trim slider
                    RangeSlider(
                        value: Binding(
                            get: { currentTime },
                            set: { newValue in
                                currentTime = newValue
                                player?.seek(to: CMTime(seconds: newValue, preferredTimescale: 600))
                            }
                        ),
                        start: $trimStartTime,
                        end: $trimEndTime,
                        bounds: 0...duration
                    )
                    .padding(.horizontal)
                    
                    // Playback controls
                    HStack(spacing: 30) {
                        Button(action: {
                            player?.seek(to: CMTime(seconds: trimStartTime, preferredTimescale: 600))
                        }) {
                            Image(systemName: "backward.end.fill")
                                .font(.title2)
                        }
                        
                        Button(action: {
                            if isPlaying {
                                player?.pause()
                            } else {
                                player?.play()
                            }
                            isPlaying.toggle()
                        }) {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.title)
                        }
                        
                        Button(action: {
                            player?.seek(to: CMTime(seconds: trimEndTime, preferredTimescale: 600))
                        }) {
                            Image(systemName: "forward.end.fill")
                                .font(.title2)
                        }
                    }
                    .padding()
                }
                
                Spacer()
                
                // Save button
                Button(action: {
                    Task {
                        await saveEditedVideo()
                    }
                }) {
                    ZStack {
                        if isSaving {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Text("Save")
                                .fontWeight(.semibold)
                        }
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(isSaving ? Color.gray : Color.blue)
                    .cornerRadius(25)
                    .padding(.horizontal)
                }
                .disabled(isSaving)
                .padding(.bottom)
            }
            .navigationTitle("Edit Video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }
            }
        }
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
    
    private func setupPlayer() {
        let asset = AVAsset(url: videoURL)
        let playerItem = AVPlayerItem(asset: asset)
        player = AVPlayer(playerItem: playerItem)
        
        // Get video duration using async/await
        Task {
            do {
                let duration = try await asset.load(.duration).seconds
                await MainActor.run {
                    self.duration = duration
                    self.trimEndTime = duration
                }
            } catch {
                print("Error loading duration: \(error)")
            }
        }
        
        // Setup time observation
        player?.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { time in
            currentTime = time.seconds
            
            // Loop playback within trim range
            if currentTime >= trimEndTime {
                player?.seek(to: CMTime(seconds: trimStartTime, preferredTimescale: 600))
            }
        }
    }
    
    private func saveEditedVideo() async {
        await MainActor.run {
            isSaving = true
            errorMessage = nil
        }
        
        do {
            let asset = AVAsset(url: videoURL)
            
            // Create composition
            let composition = AVMutableComposition()
            
            // Setup video track
            guard let compositionVideoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                throw NSError(domain: "VideoEditing", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create composition track"])
            }
            
            // Get video track
            let videoTrack = try await asset.loadTracks(withMediaType: .video).first
            guard let videoTrack = videoTrack else {
                throw NSError(domain: "VideoEditing", code: -1, userInfo: [NSLocalizedDescriptionKey: "No video track found"])
            }
            
            // Setup audio track if available
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            var compositionAudioTrack: AVMutableCompositionTrack?
            if !audioTracks.isEmpty {
                compositionAudioTrack = composition.addMutableTrack(
                    withMediaType: .audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                )
            }
            
            // Set the time range for trimming
            let timeRange = CMTimeRange(
                start: CMTime(seconds: trimStartTime, preferredTimescale: 600),
                end: CMTime(seconds: trimEndTime, preferredTimescale: 600)
            )
            
            // Add the trimmed video segment to the composition
            try compositionVideoTrack.insertTimeRange(
                timeRange,
                of: videoTrack,
                at: .zero
            )
            
            // Add audio if available
            if let audioTrack = audioTracks.first,
               let compositionAudioTrack = compositionAudioTrack {
                try compositionAudioTrack.insertTimeRange(
                    timeRange,
                    of: audioTrack,
                    at: .zero
                )
            }
            
            // Copy the original transform to preserve orientation
            let originalTransform = try await videoTrack.load(.preferredTransform)
            compositionVideoTrack.preferredTransform = originalTransform
            
            // Create export session
            let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mov")
            guard let exportSession = AVAssetExportSession(
                asset: composition,
                presetName: AVAssetExportPresetHighestQuality
            ) else {
                throw NSError(domain: "VideoEditing", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create export session"])
            }
            
            exportSession.outputURL = outputURL
            exportSession.outputFileType = .mov
            
            // Copy original video dimensions
            let naturalSize = try await videoTrack.load(.naturalSize)
            let transform = try await videoTrack.load(.preferredTransform)
            let isPortrait = transform.a == 0 && abs(transform.b) == 1
            exportSession.videoComposition = AVMutableVideoComposition(asset: composition) { request in
                let composition = AVVideoComposition(request: request)
                return composition
            }
            exportSession.videoComposition?.renderSize = isPortrait ? 
                CGSize(width: naturalSize.height, height: naturalSize.width) :
                naturalSize
            
            // Export the video
            await exportSession.export()
            
            if exportSession.status == .completed {
                // Pass the edited video URL back and dismiss
                await MainActor.run {
                    onSave(outputURL)
                    dismiss()
                }
            } else if let error = exportSession.error {
                throw error
            } else {
                throw NSError(domain: "VideoEditing", code: -1, userInfo: [NSLocalizedDescriptionKey: "Export failed with unknown error"])
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isSaving = false
            }
        }
    }
    
    private func formatTime(_ timeInSeconds: Double) -> String {
        let minutes = Int(timeInSeconds / 60)
        let seconds = Int(timeInSeconds.truncatingRemainder(dividingBy: 60))
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct RangeSlider: View {
    @Binding var value: Double
    @Binding var start: Double
    @Binding var end: Double
    let bounds: ClosedRange<Double>
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Track
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 4)
                
                // Selected range
                Rectangle()
                    .fill(Color.blue)
                    .frame(width: width(for: end - start, in: geometry),
                           height: 4)
                    .offset(x: position(for: start, in: geometry))
                
                // Start handle
                Circle()
                    .fill(Color.white)
                    .frame(width: 20, height: 20)
                    .shadow(radius: 2)
                    .offset(x: position(for: start, in: geometry) - 10)
                    .gesture(dragGesture(for: .start, in: geometry))
                
                // End handle
                Circle()
                    .fill(Color.white)
                    .frame(width: 20, height: 20)
                    .shadow(radius: 2)
                    .offset(x: position(for: end, in: geometry) - 10)
                    .gesture(dragGesture(for: .end, in: geometry))
                
                // Current position indicator
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2, height: 20)
                    .offset(x: position(for: value, in: geometry) - 1)
            }
        }
        .frame(height: 20)
    }
    
    private enum DragState {
        case start, end
    }
    
    private func position(for value: Double, in geometry: GeometryProxy) -> CGFloat {
        let range = bounds.upperBound - bounds.lowerBound
        let percentage = (value - bounds.lowerBound) / range
        return percentage * geometry.size.width
    }
    
    private func width(for value: Double, in geometry: GeometryProxy) -> CGFloat {
        let range = bounds.upperBound - bounds.lowerBound
        let percentage = value / range
        return percentage * geometry.size.width
    }
    
    private func dragGesture(for state: DragState, in geometry: GeometryProxy) -> some Gesture {
        DragGesture()
            .onChanged { gesture in
                let range = bounds.upperBound - bounds.lowerBound
                let percentage = gesture.location.x / geometry.size.width
                let value = bounds.lowerBound + (range * percentage)
                let clampedValue = max(bounds.lowerBound, min(bounds.upperBound, value))
                
                switch state {
                case .start:
                    start = min(clampedValue, end - 1)
                case .end:
                    end = max(clampedValue, start + 1)
                }
            }
    }
} 