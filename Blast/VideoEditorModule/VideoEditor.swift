import IMGLYEditor
import SwiftUI

/// Built to support versatile video editing capabilities for a broad range of video applications.
public struct VideoEditor: View {
    /// Scene that will be loaded by the default implementation of the `onCreate` callback.
    public static let defaultScene = Bundle.module.url(forResource: "video-empty", withExtension: "scene")!
    
    @Environment(\.imglyOnCreate) private var onCreate
    @Environment(\.imglyDock) private var dock
    @Environment(\.dismiss) private var dismiss
    
    private let settings: EngineSettings
    private let onExport: ((URL) -> Void)?
    
    /// Creates a video editor with settings and optional export handler
    /// - Parameters:
    ///   - settings: The settings to initialize the underlying engine
    ///   - onExport: Optional callback when video is exported
    public init(_ settings: EngineSettings, onExport: ((URL) -> Void)? = nil) {
        self.settings = settings
        self.onExport = onExport
    }
    
    public var body: some View {
        EditorUI(zoomPadding: 1)
            .navigationTitle("")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        UndoRedoButtons()
                        ExportButton()
                    }
                    .labelStyle(.adaptiveIconOnly)
                }
            }
            .imgly.editor(settings, behavior: .video)
            .imgly.onCreate { engine in
                guard let onCreate else {
                    try await OnCreate.loadScene(from: Self.defaultScene)(engine)
                    return
                }
                try await onCreate(engine)
            }
            .imgly.onExport { engine, _ in
                if let outputURL = try? await engine.scene.export() {
                    onExport?(outputURL)
                    dismiss()
                }
            }
            .imgly.dock { context in
                if let dock {
                    try dock(context)
                } else {
                    Dock.Buttons.photoRoll()
                    Dock.Buttons.imglyCamera()
                    Dock.Buttons.overlaysLibrary()
                    Dock.Buttons.textLibrary()
                    Dock.Buttons.stickersAndShapesLibrary()
                    Dock.Buttons.audioLibrary()
                    Dock.Buttons.voiceover()
                    Dock.Buttons.reorder()
                }
            }
    }
}

struct VideoEditor_Previews: PreviewProvider {
    static var previews: some View {
        defaultPreviews
    }
} 