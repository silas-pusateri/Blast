@_spi(Internal) import IMGLYCamera
import IMGLYEditor
import Foundation

public extension OnCreate {
    /// Creates a callback that loads the output of the camera as scene and the default and demo asset sources.
    /// - Parameter result: The camera result to load a scene with.
    /// - Returns: The callback.
    static func loadVideos(from result: CameraResult) -> Callback {
        { engine in
            try await engine.createScene(from: result)
            try await loadAssetSources(engine)
        }
    }
    
    /// Creates a callback that loads the video as scene and sets up default asset sources
    /// - Parameter videoURL: The URL of the video to load
    /// - Returns: The callback
    static func loadVideo(from videoURL: URL) -> Callback {
        { engine in
            try await engine.createScene(from: videoURL)
        { engine, _ in
            try await engine.scene.load(from: videoURL)
        }
    }
} 