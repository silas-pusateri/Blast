//
//  CameraManager.swift
//  Blast
//
//  Created by Silas Pusateri on 2/6/25.
//

import Foundation
import AVFoundation
import SwiftUI

// Camera manager to handle AVFoundation functionality
class CameraManager: NSObject, ObservableObject {
    let session = AVCaptureSession()
    var videoDeviceInput: AVCaptureDeviceInput?
    let movieOutput = AVCaptureMovieFileOutput()
    @Published var isSimulator: Bool
    var recordingCompletion: ((URL) -> Void)?
    
    override init() {
        #if targetEnvironment(simulator)
        self.isSimulator = true
        #else
        self.isSimulator = false
        #endif
        super.init()
    }
    
    func checkPermissions() {
        if isSimulator { return }
        
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    DispatchQueue.main.async {
                        self.setupSession()
                    }
                }
            }
        default:
            break
        }
    }
    
    func setupSession() {
        if isSimulator { return }
        
        session.beginConfiguration()
        
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                       for: .video,
                                                       position: .back) else { return }
        
        do {
            videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
            if session.canAddInput(videoDeviceInput!) {
                session.addInput(videoDeviceInput!)
            }
            
            if session.canAddOutput(movieOutput) {
                session.addOutput(movieOutput)
            }
        } catch {
            print("Error setting up camera: \(error.localizedDescription)")
            return
        }
        
        session.commitConfiguration()
        
        DispatchQueue.global(qos: .userInitiated).async {
            self.session.startRunning()
        }
    }
    
    func switchCamera() {
        guard let currentInput = videoDeviceInput else { return }
        
        let currentPosition = currentInput.device.position
        let newPosition: AVCaptureDevice.Position = currentPosition == .back ? .front : .back
        
        guard let newDevice = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                     for: .video,
                                                     position: newPosition) else { return }
        
        session.beginConfiguration()
        session.removeInput(currentInput)
        
        do {
            let newVideoInput = try AVCaptureDeviceInput(device: newDevice)
            if session.canAddInput(newVideoInput) {
                session.addInput(newVideoInput)
                videoDeviceInput = newVideoInput
            }
        } catch {
            print("Error switching camera: \(error.localizedDescription)")
            session.addInput(currentInput)
        }
        
        session.commitConfiguration()
    }
    
    func startRecording(completion: @escaping (URL) -> Void) {
        recordingCompletion = completion
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let fileUrl = paths[0].appendingPathComponent("\(UUID().uuidString).mov")
        movieOutput.startRecording(to: fileUrl, recordingDelegate: self)
    }
    
    func stopRecording() {
        movieOutput.stopRecording()
    }
}

extension CameraManager: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput,
                   didFinishRecordingTo outputFileURL: URL,
                   from connections: [AVCaptureConnection],
                   error: Error?) {
        if error == nil {
            DispatchQueue.main.async {
                self.recordingCompletion?(outputFileURL)
            }
        }
    }
}