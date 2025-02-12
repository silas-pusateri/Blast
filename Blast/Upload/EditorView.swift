import IMGLYVideoEditor
import SwiftUI
import AVFoundation

struct EditorView: View {
    @Environment(\.dismiss) var dismiss
    let videoURL: URL
    let isSuggestMode: Bool
    let onSave: (URL, [String: Any]?) -> Void
    
    // Add state for export process
    @State private var isExporting = false
    @State private var exportProgress: Float = 0
    @State private var exportError: Error?
    
    private let settings = EngineSettings(
        license: Secrets.licenseKey,
        userID: "<your unique user id>"
    )
    
    // Add coordinator state object
    @StateObject private var coordinator: VideoEditorStateObject
    
    init(videoURL: URL, isSuggestMode: Bool = false, onSave: @escaping (URL, [String: Any]?) -> Void) {
        self.videoURL = videoURL
        self.isSuggestMode = isSuggestMode
        self.onSave = onSave
        self._coordinator = StateObject(wrappedValue: VideoEditorStateObject())
    }
    
    init(video: Video, isSuggestMode: Bool = false, onSave: @escaping (URL, [String: Any]?) -> Void) {
        guard let url = URL(string: video.url) else {
            fatalError("Invalid video URL")
        }
        self.init(videoURL: url, isSuggestMode: isSuggestMode, onSave: onSave)
    }
    
    private func createMetadata(from outputURL: URL) -> [String: Any] {
        return [
            "editedAt": Date().timeIntervalSince1970,
            "originalURL": videoURL.absoluteString
        ]
    }
    
    private func handleExportCompletion(url: URL) {
        let metadata = createMetadata(from: url)
        onSave(url, metadata)
        dismiss()
    }
    
    var editor: some View {
        VideoEditor(settings)
            .modifier(EditorConfiguration(coordinator: coordinator))
    }
    
    var body: some View {
        ModalEditor(editor: {
            ZStack {
                editor
                
                if isExporting {
                    ExportOverlay(progress: exportProgress)
                }
            }
        }, dismissLabel: {
            SwiftUI.Label("Preview", systemImage: "eye")
        }, onDismiss: {
            // Start export process without parameters
            isExporting = true
            coordinator.startExport()
        })
        .alert("Export Failed", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK", role: .cancel) {
                exportError = nil
            }
        } message: {
            Text(exportError?.localizedDescription ?? "Unknown error")
        }
        .onChange(of: coordinator.exportedURL) { newURL in
            if let url = newURL {
                handleExportCompletion(url: url)
                coordinator.resetExportedURL()
            }
        }
    }
}

// MARK: - Export Overlay View
private struct ExportOverlay: View {
    let progress: Float
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
            VStack {
                ProgressView("Exporting...", value: progress, total: 1.0)
                    .progressViewStyle(.linear)
                    .padding()
                Text("\(Int(progress * 100))%")
                    .foregroundColor(.white)
            }
            .frame(maxWidth: 200)
            .background(Color(.systemBackground))
            .cornerRadius(10)
            .padding()
        }
        .ignoresSafeArea()
    }
}

// MARK: - Editor Configuration Modifier
private struct EditorConfiguration: ViewModifier {
    let coordinator: VideoEditorStateObject
    
    func body(content: Content) -> some View {
        content.onAppear {
            if let editor = content as? VideoEditor {
                coordinator.configureEditor(editor: editor)
            }
        }
    }
}

// MARK: - State Object for Coordinator
private class VideoEditorStateObject: ObservableObject, VideoEditorDelegate {
    @Published var isExporting = false
    @Published var exportProgress: Float = 0
    @Published var exportError: Error?
    @Published var exportedURL: URL?
    
    private var coordinator: VideoEditorCoordinator?
    
    init() {
        coordinator = VideoEditorCoordinator(delegate: self)
    }
    
    func configureEditor(editor: VideoEditor) {
        coordinator?.configure(editor: editor)
    }
    
    func startExport() {
        isExporting = true
        exportProgress = 0
        exportError = nil
        exportedURL = nil
        coordinator?.exportVideo()
    }
    
    func resetExportedURL() {
        exportedURL = nil
    }
    
    func editorDidFinishExport(url: URL) {
        DispatchQueue.main.async {
            self.isExporting = false
            self.exportedURL = url
        }
    }
    
    func editorDidFailExport(error: Error) {
        DispatchQueue.main.async {
            self.isExporting = false
            self.exportError = error
        }
    }
    
    func editorExportProgress(_ progress: Float) {
        DispatchQueue.main.async {
            self.exportProgress = progress
        }
    }
    
    deinit {
        coordinator?.cleanup()
    }
}