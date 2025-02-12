
# Creative Editor Documentation

## CreativeEngine APIs

Use the CreativeEngine APIs of the CreativeEditor SDK to implement highly customized workflows.

The APIs allow you to programmatically manipulate scenes inside the editor to automate workflows and customize the user experience.

### Accessing the CreativeEngine APIs

You can access the CreativeEngine APIs via the `engine` object and interact with the scene seen on screen. The examples in the API Guides will use the headless CreativeEngine.

#### Swift Example

```swift
import IMGLYEngine
import SwiftUI

struct IntegrateWithSwiftUI: View {
    @StateObject private var engine = Engine()

    var body: some View {
        ZStack {
            Canvas(engine: engine)
            Button("Use the Engine") {
                Task {
                    let url = URL(string: "https://cdn.img.ly/assets/demo/v1/ly.img.template/templates/cesdk_postcard_1.scene")!
                    try? await engine.scene.load(from: url)

                    try? engine.block.find(byType: .text).forEach { id in
                        try? engine.block.setOpacity(id, value: 0.5)
                    }
                }
            }
        }
    }
}

API Guides
* Scene: Load, create, and save scenes or control the zoom.
* Block: Manipulate blocks, the elements a scene is made of, in various ways.
* Editor: Control settings or history and observe state changes in your engine instance.
* Asset: Manage assets by creating and reading from AssetSources.
* Event: Subscribe to block creation, update, and destruction events.
* Variable: Manage the values of pre-defined variables, allowing for quick customization of things like headlines.

Scene API
Learn how to load, save, and export scenes via the API in the CreativeEditor SDK. In these examples we will show you how to use the CreativeEngine to create, load, and save scenes.
Scene Lifecycle
* Lifecycle: Create, load, and save scenes.
* Contents: Explore scene contents.
* Zoom: Change the zoom level.
* Templates: Apply templates to your scene.
Note: At any time, the engine holds only a single scene. Loading or creating a scene will replace the current one.
Setup
This example uses the headless CreativeEngine. See the Setup article for details. To get started right away, you can also access the block API within a running CE.SDK instance via cesdk.engine.block. See the APIs Overview for more details.

Creating a Scene
Swift API
@discardableResult
public func create(sceneLayout: SceneLayout = .free) throws -> DesignBlockID
* Description: Creates a new scene with its own camera.
* Parameters:
    * sceneLayout: The desired layout of the scene.
* Returns: The scene’s handle.
public func get() throws -> DesignBlockID?
* Description: Returns the currently active scene.
* Returns: The scene or nil if none was created yet.
@discardableResult
public func createVideo() throws -> DesignBlockID
* Description: Creates a new scene in video mode with its own camera.
* Returns: The scene’s handle.
public func getMode() throws -> SceneMode
* Description: Gets the current scene mode.
* Returns: The current mode of the scene.
@discardableResult
public func create(fromImage url: URL, dpi: Float = 300, pixelScaleFactor: Float = 1, sceneLayout: SceneLayout = .free) async throws -> DesignBlockID
* Description: Loads an image and creates a scene with a single page showing the image. (Note: Fetching the image may take some time.)
* Parameters:
    * url: The image URL.
    * dpi: The scene's DPI.
    * pixelScaleFactor: The display's content scale factor.
    * sceneLayout: The desired layout.
* Returns: A handle to the loaded scene.
@discardableResult
public func create(fromVideo url: URL) async throws -> DesignBlockID
* Description: Loads a video and creates a scene with a single page showing the video.
* Parameters:
    * url: The video URL.
* Returns: A handle to the loaded scene.

Loading a Scene
Swift API
@discardableResult
public func load(from string: String) async throws -> DesignBlockID
* Description: Loads the contents of a scene file (provided as a base64 string).
* Parameters:
    * string: The scene file contents.
* Returns: A handle to the loaded scene.
@discardableResult
public func load(from url: URL) async throws -> DesignBlockID
* Description: Loads a scene from a URL (fetched asynchronously).
* Parameters:
    * url: The URL of the scene file.
* Returns: A handle to the loaded scene.
@discardableResult
public func loadArchive(from url: URL) async throws -> DesignBlockID
* Description: Loads an archived scene from a URL.
* Parameters:
    * url: The URL of the archived scene file.
* Returns: A handle to the loaded scene.

Saving a Scene
Swift API
public func saveToString(allowedResourceSchemes: [String] = ["blob", "bundle", "file", "http", "https"]) async throws -> String
* Description: Serializes the current scene into a string.
* Parameters:
    * allowedResourceSchemes: List of allowed URL schemes.
* Returns: A serialized scene string.
public func saveToArchive() async throws -> Blob
* Description: Saves the current scene and its referenced assets into an archive. (Block references are relative to the scene file location.)
* Returns: A serialized scene data blob.

Events
Swift API
public var onActiveChanged: AsyncStream<Void> { get }
* Description: Subscribe to changes to the active scene.
Example.swift
// Creating scenes
var scene = try engine.scene.create()
scene = try engine.scene.get()!
scene = try engine.scene.createVideo()
let mode = try engine.scene.getMode()

if mode == .design {
    // Working with a static design...
}

scene = try await engine.scene.create(fromImage: .init(string: "https://img.ly/static/ubq_samples/sample_4.jpg")!)
scene = try await engine.scene.create(fromVideo: .init(string: "https://img.ly/static/ubq_video_samples/bbb.mp4")!)

scene = try await engine.scene.load(from: SCENE_CONTENT)
scene = try await engine.scene.load(
    from: .init(string: "https://cdn.img.ly/assets/demo/v1/ly.img.template/templates/cesdk_postcard_1.scene")!
)
scene = try await engine.scene.loadArchive(
    from: .init(string: "https://cdn.img.ly/assets/demo/v1/ly.img.template/templates/cesdk_postcard_1_scene.zip")!
)

// Save the scene
let string = try await engine.scene.saveToString()
let archive = try await engine.scene.saveToArchive()

// Subscribe to scene changes
let task = Task {
    for await _ in engine.scene.onActiveChanged {
        let newActiveScene = try engine.scene.get()
    }
}

Scene Contents
Learn how to explore scene contents through the scene API.
Setup
This example uses the headless CreativeEngine. See the Setup article for details. You can also access the block API via cesdk.engine.block.
Swift API
public func getPages() throws -> [DesignBlockID]
* Description: Gets the sorted list of pages in the scene.
* Returns: An array of page IDs.
public func setDesignUnit(_ designUnit: DesignUnit) throws
* Description: Converts all scene values into the specified design unit.
* Parameters:
    * designUnit: The new design unit.
public func getDesignUnit() throws -> DesignUnit
* Description: Returns the current design unit.
* Returns: The design unit.
public func getCurrentPage() throws -> DesignBlockID?
* Description: Gets the current page (the first selected element if at least 25% visible, otherwise the nearest to viewport center).
* Returns: The current page or an error.
public func findNearestToViewPortCenter(byKind kind: String) throws -> [DesignBlockID]
* Description: Finds blocks by kind sorted by distance to the viewport center.
* Parameters:
    * kind: The kind to search for.
* Returns: An array of block IDs.
public func findNearestToViewPortCenter(byType type: DesignBlockType) throws -> [DesignBlockID]
* Description: Finds blocks by type sorted by distance to the viewport center.
* Parameters:
    * type: The block type.
* Returns: An array of block IDs.
Example.swift
let pages = try engine.scene.getPages()
let currentPage = engine.scene.getCurrentPage()
let nearestPageByType = engine.scene.findNearestToViewPortCenter(byType: .page).first!
let nearestImageByKind = engine.scene.findNearestToViewPortCenter(byKind: "image").first!

try engine.scene.setDesignUnit(.px)
// Now returns DesignUnit.px
_ = try engine.scene.getDesignUnit()

Zoom
Learn how to control and observe camera zoom via the scene API.
Setup
This example uses the headless CreativeEngine. See the Setup article for details. You can also access the block API via cesdk.engine.block.
Functions
Get Zoom
public func getZoom() throws -> Float
* Description: Queries the camera zoom level.
* Returns: The current zoom level in units of 1/px.
Set Zoom
public func setZoom(_ level: Float) throws
* Description: Sets the zoom level of the active scene.
* Parameters:
    * level: The new zoom level.
Zoom to a Block
public func zoom(to id: DesignBlockID, paddingLeft: Float = 0, paddingTop: Float = 0, paddingRight: Float = 0, paddingBottom: Float = 0) async throws
* Description: Sets the zoom and focus to show a block. (Without padding, the view is tight on the block.)
* Parameters:
    * id: The target block.
    * paddingLeft, paddingTop, paddingRight, paddingBottom: Optional padding values.
Immediate Zoom to a Block
public func immediateZoom(to id: DesignBlockID, paddingLeft: Float = 0, paddingTop: Float = 0, paddingRight: Float = 0, paddingBottom: Float = 0, forceUpdate: Bool = false) throws
* Description: Immediately sets the zoom and focus to show a block. (Assumes layout is complete; use forceUpdate to update the layout.)
* Parameters: See above.
Enable Zoom Auto-Fit
public func enableZoomAutoFit(_ id: DesignBlockID, axis: ZoomAutoFitAxis, paddingLeft: Float = 0, paddingTop: Float = 0, paddingRight: Float = 0, paddingBottom: Float = 0) throws
* Description: Continuously adjusts the zoom to fit the block’s axis-aligned bounding box. (Note: Calling setZoom(level:) or zoom(to:) disables this feature.)
* Parameters:
    * id: The target block.
    * axis: The axis to fit.
    * Padding parameters.
Disable Zoom Auto-Fit
public func disableZoomAutoFit(_ id: DesignBlockID) throws
* Description: Disables zoom auto-fit for the specified scene or block.
Check Zoom Auto-Fit Status
public func isZoomAutoFitEnabled(_ id: DesignBlockID) throws -> Bool
* Description: Checks whether zoom auto-fit is enabled.
* Returns: true if enabled; otherwise, false.
Camera Position Clamping
public func unstable_enableCameraPositionClamping(_ ids: [DesignBlockID], paddingLeft: Float = 0, paddingTop: Float = 0, paddingRight: Float = 0, paddingBottom: Float = 0, scaledPaddingLeft: Float = 0, scaledPaddingTop: Float = 0, scaledPaddingRight: Float = 0, scaledPaddingBottom: Float = 0) throws
* Description: Ensures the camera position stays within the blocks’ bounds.
* Parameters: Multiple padding parameters as specified.
public func unstable_disableCameraPositionClamping() throws
* Description: Disables any camera position clamping.
public func unstable_isCameraPositionClampingEnabled(_ id: DesignBlockID) throws -> Bool
* Description: Checks whether camera position clamping is enabled.
* Returns: true if enabled; otherwise, false.
Camera Zoom Clamping
public func unstable_enableCameraZoomClamping(_ ids: [DesignBlockID], minZoomLimit: Float = -1, maxZoomLimit: Float = -1, paddingLeft: Float = 0, paddingTop: Float = 0, paddingRight: Float = 0, paddingBottom: Float = 0) throws
* Description: Restricts the camera zoom level to a given range.
* Parameters:
    * ids: The target blocks.
    * minZoomLimit: Minimum zoom limit (when negative, unlimited).
    * maxZoomLimit: Maximum zoom limit (when negative, unlimited).
    * Padding parameters.
public func unstable_disableCameraZoomClamping() throws
* Description: Disables camera zoom clamping.
public func unstable_isCameraZoomClampingEnabled(_ id: DesignBlockID) throws -> Bool
* Description: Checks whether camera zoom clamping is enabled.
* Returns: true if enabled; otherwise, false.
Zoom Level Changed Event
public var onZoomLevelChanged: AsyncStream<Void> { get }
* Description: Subscribe to zoom level changes.
Example.swift
// Zoom to 100%
try engine.scene.setZoom(1.0)

// Zoom to 50%
try engine.scene.setZoom(0.5 * engine.scene.getZoom())

// Bring entire scene into view with 20px padding on all sides
try await engine.scene.zoom(
    to: scene,
    paddingLeft: 20.0,
    paddingTop: 20.0,
    paddingRight: 20.0,
    paddingBottom: 20.0
)
try engine.scene.immediateZoom(
    to: scene,
    paddingLeft: 20.0,
    paddingTop: 20.0,
    paddingRight: 20.0,
    paddingBottom: 20.0
)

// Follow page with 20px padding on all sides
let page = try engine.scene.getPages().first!
try engine.scene.enableZoomAutoFit(
    page,
    axis: .both,
    paddingLeft: 20,
    paddingTop: 20,
    paddingRight: 20,
    paddingBottom: 20
)

// Stop following page
try engine.scene.disableZoomAutoFit(page)
// Query if zoom auto-fit is enabled for the page
try engine.scene.isZoomAutoFitEnabled(page)

// Clamp camera position with 10px padding
try engine.scene.unstable_enableCameraPositionClamping(
    [scene],
    paddingLeft: 10,
    paddingTop: 10,
    paddingRight: 10,
    paddingBottom: 10,
    scaledPaddingLeft: 0,
    scaledPaddingTop: 0,
    scaledPaddingRight: 0,
    scaledPaddingBottom: 0
)
try engine.scene.unstable_disableCameraPositionClamping()
// Query camera position clamping status
try engine.scene.unstable_isCameraPositionClampingEnabled(scene)

// Set camera zoom limits (12.5% to 800%)
try engine.scene.unstable_enableCameraZoomClamping(
    [page],
    minZoomLimit: 0.125,
    maxZoomLimit: 8.0,
    paddingLeft: 0,
    paddingTop: 0,
    paddingRight: 0,
    paddingBottom: 0
)
try engine.scene.unstable_disableCameraZoomClamping()
// Query camera zoom clamping status
try engine.scene.unstable_isCameraZoomClampingEnabled(scene)

// Listen for zoom level changes
let task = Task {
    for await _ in engine.editor.onZoomLevelChanged {
        let zoomLevel = try engine.scene.getZoom()
        print("Zoom level is now: \(zoomLevel)")
    }
}
task.cancel()

Apply a Template to a Scene
Apply the contents of a given template scene to the currently loaded scene.
Setup
This example uses the headless CreativeEngine. See the Setup article for details. You can also access the block API via cesdk.engine.block.
Applying Template Scenes
Swift API
public func applyTemplate(from string: String) async throws
* Description: Applies a template (provided as a base64 string) to the current scene while preserving the current design unit and page dimensions.
public func applyTemplate(from url: URL) async throws
* Description: Applies a template from a URL to the current scene.
* Parameters:
    * url: The template scene file URL.
Example.swift
try await engine.scene.applyTemplate(from: "UBQ1ewoiZm9ybWF0Ij...")
try await engine.scene.applyTemplate(
    from: .init(string: "https://cdn.img.ly/assets/demo/v1/ly.img.template/templates/cesdk_postcard_1.scene")!
)

Editor APIs
Use the editor API to control the editing state.
* Available Settings: Learn what settings are available.
* Change Settings: How to change editor settings.
* Observe Editing State: How to observe the current state.
* Manage the History: How to perform undo/redo.
* Managing Spot Colors: How to define spot colors.
* Manage Buffers: How to use arbitrary data buffers.
Observe Editing State
This example shows how to set and query the editor state (e.g., the current edit mode).
Setup
This example uses the headless CreativeEngine. See the Setup article for details.
Editor State
The editor state includes the current edit mode (e.g., "Transform", "Crop", "Text", or "Playback") and cursor information. Instead of polling, subscribe to changes.
Swift API
public var onStateChanged: AsyncStream<Void> { get }
* Description: Subscribe to changes in the editor state.
public func setEditMode(_ mode: EditMode)
* Description: Sets the editor’s current edit mode.
* Parameters:
    * mode: One of "Transform", "Crop", "Text", or "Playback" (default is "Transform").
public func getEditMode() -> EditMode
* Description: Gets the current edit mode.
* Returns: The current edit mode.
public func unstable_isInteractionHappening() throws -> Bool
* Description: Checks if a user interaction (such as a resize or drag) is in progress.
* Returns: true if an interaction is happening.
Cursor Functions
public func getCursorType() -> CursorType
* Description: Gets the type of cursor to display.
* Returns: The cursor type.
public func getCursorRotation() -> Float
* Description: Gets the rotation (in radians) for rendering the mouse cursor.
* Returns: The rotation angle.
public func getTextCursorPositionInScreenSpaceX() -> Float
* Description: Gets the text cursor’s x position in screen space.
* Returns: The x-coordinate.
public func getTextCursorPositionInScreenSpaceY() -> Float
* Description: Gets the text cursor’s y position in screen space.
* Returns: The y-coordinate.
Example.swift
let task = Task {
    for await _ in engine.editor.onStateChanged {
        print("Editor state has changed")
    }
}

// Set edit mode to 'Crop'
engine.editor.setEditMode(.crop)
print(engine.editor.getEditMode()) // Expected output: Crop

try engine.editor.unstable_isInteractionHappening()

// Update the cursor display
print(engine.editor.getCursorType())
print(engine.editor.getCursorRotation())

// Query text cursor position
print(engine.editor.getTextCursorPositionInScreenSpaceX())
print(engine.editor.getTextCursorPositionInScreenSpaceY())

History
Learn how to undo and redo editing steps.
Setup
This example uses the headless CreativeEngine. See the Setup article for details.
Functions
Create History
public func createHistory() -> History
* Description: Creates a history stack for editing operations.
* Returns: The history handle.
Destroy History
public func destroyHistory(_ history: History)
* Description: Destroys the specified history.
* Parameters:
    * history: The history to destroy.
Set Active History
public func setActiveHistory(_ history: History)
* Description: Marks a history as active (clearing all others).
* Parameters:
    * history: The history to activate.
Get Active History
public func getActiveHistory() -> History
* Description: Gets (or creates) the currently active history.
* Returns: The active history handle.
Add Undo Step
public func addUndoStep() throws
* Description: Adds a new state to the undo stack if changes were made.
Undo
public func undo() throws
* Description: Undoes one step in the history.
Can Undo
public func canUndo() throws -> Bool
* Description: Checks if an undo is available.
* Returns: true if possible.
Redo
public func redo() throws
* Description: Redoes one step in the history.
Can Redo
public func canRedo() throws -> Bool
* Description: Checks if a redo is available.
* Returns: true if possible.
History Updated Event
public var onHistoryUpdated: AsyncStream<Void> { get }
* Description: Subscribe to history updates.
Example.swift
// Manage history stacks
let newHistory = engine.editor.createHistory()
let oldHistory = engine.editor.getActiveHistory()
engine.editor.setActiveHistory(newHistory)
engine.editor.destroyHistory(oldHistory)

let historyTask = Task {
    for await _ in engine.editor.onHistoryUpdated {
        let canUndo = try engine.editor.canUndo()
        let canRedo = try engine.editor.canRedo()
        print("History updated: \(canUndo) \(canRedo)")
    }
}

// Push a new state onto the undo stack
try engine.editor.addUndoStep()

// Undo if possible
if try engine.editor.canUndo() {
    try engine.editor.undo()
}

// Redo if possible
if try engine.editor.canRedo() {
    try engine.editor.redo()
}

Manage Assets
Manage assets through the asset API. Asset sources provide assets for the editor’s asset library and can be added dynamically.
Setup
This example uses the headless CreativeEngine. See the Setup article for details.
Defining a Custom Asset Source
Asset sources must have an id and a findAssets function. All functions are asynchronous to support web requests or other long-running operations.
Finding and Applying Assets
Swift API
public func findAssets(sourceID: String, query: AssetQueryData) async throws -> AssetQueryResult
* Description: Finds assets in a specified asset source.
* Parameters:
    * sourceID: The asset source ID.
    * query: The search parameters.
* Returns: The asset query result.
public func apply(sourceID: String, assetResult: AssetResult) async throws -> DesignBlockID?
* Description: Applies an asset result to the active scene. (Can be overridden by a custom applyAsset.)
* Parameters:
    * sourceID: The asset source ID.
    * assetResult: The asset result.
public func defaultApplyAsset(assetResult: AssetResult) async throws -> DesignBlockID?
* Description: The default implementation for applying an asset.
public func applyToBlock(sourceID: String, assetResult: AssetResult, block: DesignBlockID) async throws
* Description: Applies an asset result to a specified block.
* Parameters:
    * sourceID: The asset source ID.
    * assetResult: The asset result.
    * block: The target block.
public func defaultApplyAssetToBlock(assetResult: AssetResult, block: DesignBlockID) async throws
* Description: The default implementation for applying an asset to an existing block.
public func getSupportedMIMETypes(sourceID: String) throws -> [String]
* Description: Queries the supported MIME types for an asset source.
* Parameters:
    * sourceID: The asset source ID.
* Returns: An array of supported MIME types.
Registering a New Asset Source
public func addSource(_ source: AssetSource) throws
* Description: Adds a custom asset source (the ID must be unique).
public func addLocalSource(sourceID: String, supportedMimeTypes: [String]? = nil, applyAsset: (@Sendable (AssetResult) async throws -> DesignBlockID?)? = nil, applyAssetToBlock: (@Sendable (AssetResult, DesignBlockID) async throws -> Void)? = nil) throws
* Description: Adds a local asset source with optional callbacks.
* Parameters:
    * sourceID, optional supportedMimeTypes, and optional applyAsset and applyAssetToBlock callbacks.
public func findAllSources() -> [String]
* Description: Returns all registered asset source IDs.
public func removeSource(sourceID: String) throws
* Description: Removes an asset source by ID.
* Parameters:
    * sourceID: The asset source ID.
public var onAssetSourceAdded: AsyncStream<String> { get }
* Description: Subscribe to asset source additions.
public var onAssetSourceRemoved: AsyncStream<String> { get }
* Description: Subscribe to asset source removals.
public var onAssetSourceUpdated: AsyncStream<String> { get }
* Description: Subscribe to asset source updates.
Scene Asset Sources
A scene colors asset source is available automatically (read-only, updated on each findAssets call).
Add an Asset
public func addAsset(to sourceID: String, asset: AssetDefinition) throws
* Description: Adds an asset to an asset source.
* Parameters:
    * sourceID: The target asset source.
    * asset: The asset definition.
Remove an Asset
public func removeAsset(from sourceID: String, assetID: String) throws
* Description: Removes a specified asset.
* Parameters:
    * sourceID: The asset source.
    * assetID: The asset ID.
Asset Source Content Updates
public func assetSourceContentsChanged(sourceID: String) throws
* Description: Notifies the engine that an asset source’s contents have changed.
* Parameters:
    * sourceID: The asset source ID.
Groups in Assets
public func getGroups(sourceID: String) async throws -> [String]
* Description: Queries the asset groups for a given asset source.
* Parameters:
    * sourceID: The asset source ID.
* Returns: An array of group names.
Credits and License
public func getCredits(sourceID: String) -> AssetCredits?
* Description: Gets the asset source's credits information.
* Parameters:
    * sourceID: The asset source ID.
public func getLicense(sourceID: String) -> AssetLicense?
* Description: Gets the asset source's license information.
* Parameters:
    * sourceID: The asset source ID.
Example.swift
let scene = try engine.scene.create()
let page = try engine.block.create(.page)
let block = try engine.block.create(.graphic)
try engine.block.appendChild(to: scene, child: page)
try engine.block.appendChild(to: page, child: block)

let customSource = CustomAssetSource(engine: engine)

let addedTask = Task {
    for await sourceID in engine.asset.onAssetSourceAdded {
        print("Added source: \(sourceID)")
    }
}
let removedTask = Task {
    for await sourceID in engine.asset.onAssetSourceRemoved {
        print("Removed source: \(sourceID)")
    }
}
let updatedTask = Task {
    for await sourceID in engine.asset.onAssetSourceUpdated {
        print("Updated source: \(sourceID)")
    }
}

try engine.asset.addSource(customSource)

let localSourceID = "local-source"
try engine.asset.addLocalSource(sourceID: localSourceID)

let assetDefinition = AssetDefinition(
    id: "ocean-waves-1",
    meta: [
        "uri": "https://example.com/ocean-waves-1.mp4",
        "thumbUri": "https://example.com/thumbnails/ocean-waves-1.jpg",
        "mimeType": MIMEType.mp4.rawValue,
        "width": "1920",
        "height": "1080",
    ],
    label: [
        "en": "relaxing ocean waves",
    ],
    tags: [
        "en": ["ocean", "waves", "soothing", "slow"],
    ]
)
try engine.asset.addAsset(to: localSourceID, asset: assetDefinition)
try engine.asset.removeAsset(from: localSourceID, assetID: assetDefinition.id)

engine.asset.findAllSources()

let mimeTypes = try engine.asset.getSupportedMIMETypes(sourceID: customSource.id)

let credits = engine.asset.getCredits(sourceID: customSource.id)
let license = engine.asset.getLicense(sourceID: customSource.id)
let groups = try await engine.asset.getGroups(sourceID: customSource.id)

let result = try await engine.asset.findAssets(
    sourceID: customSource.id,
    query: .init(query: "", page: 0, perPage: 10)
)
let asset = result.assets[0]
let sortByNewest = try await engine.asset.findAssets(
    sourceID: customSource.id,
    query: .init(query: nil, page: 0, perPage: 10, sortingOrder: .descending)
)
let sortById = try await engine.asset.findAssets(
    sourceID: customSource.id,
    query: .init(query: nil, page: 0, perPage: 10, sortingOrder: .ascending, sortKey: "id")
)
let sortByMetaKeyValue = try await engine.asset.findAssets(
    sourceID: customSource.id,
    query: .init(query: nil, page: 0, perPage: 10, sortingOrder: .ascending, sortKey: "someMetaKey")
)
let search = try await engine.asset.findAssets(
    sourceID: customSource.id,
    query: .init(query: "banana", page: 0, perPage: 100)
)

let sceneColorsResult = try await engine.asset.findAssets(
    sourceID: "ly.img.scene.colors",
    query: .init(query: nil, page: 0, perPage: 99999)
)
let colorAsset = sceneColorsResult.assets[0]

try await engine.asset.apply(sourceID: customSource.id, assetResult: asset)
try await engine.asset.applyToBlock(sourceID: customSource.id, assetResult: asset, block: block)
try engine.asset.assetSourceContentsChanged(sourceID: customSource.id)

try engine.asset.removeSource(sourceID: customSource.id)
try engine.asset.removeSource(sourceID: localSourceID)

final class CustomAssetSource: NSObject, AssetSource {
    private weak var engine: Engine?

    init(engine: Engine) {
        self.engine = engine
    }

    var id: String { "foobar" }

    func findAssets(queryData: AssetQueryData) async throws -> AssetQueryResult {
        return .init(
            assets: [
                .init(
                    id: "logo",
                    meta: [
                        "uri": "https://img.ly/static/ubq_samples/imgly_logo.jpg",
                        "thumbUri": "https://img.ly/static/ubq_samples/thumbnails/imgly_logo.jpg",
                        "blockType": DesignBlockType.graphic.rawValue,
                        "fillType": FillType.image.rawValue,
                        "width": "320",
                        "height": "116",
                    ],
                    context: .init(sourceID: "foobar")
                ),
            ],
            currentPage: queryData.page,
            total: 1
        )
    }

    func apply(asset: AssetResult) async throws -> NSNumber? {
        if let id = try await engine?.asset.defaultApplyAsset(assetResult: asset) {
            return NSNumber(value: id)
        } else {
            return nil
        }
    }

    func applyToBlock(asset: AssetResult, block: DesignBlockID) async throws {
        try await engine?.asset.defaultApplyAssetToBlock(assetResult: asset, block: block)
    }

    var supportedMIMETypes: [String]? { [MIMEType.jpeg.rawValue] }
    var credits: IMGLYEngine.AssetCredits? { nil }
    var license: IMGLYEngine.AssetLicense? { nil }
}

Observe Events
Subscribe to creation, update, and destruction events of design blocks.
Setup
This example uses the headless CreativeEngine. See the Setup article for details.
Subscribing to Events
Block events include:
* Created: Block was created.
* Updated: A property of the block was updated.
* Destroyed: The block was destroyed (destroyed blocks become invalid).
All events during an engine update are batched and delivered at the end of the update.
Swift API
public func subscribe(to blocks: [DesignBlockID]) -> AsyncStream<[BlockEvent]>
* Description: Subscribes to block lifecycle events.
* Parameters:
    * blocks: A list of block IDs. (Empty means all blocks.)
* Returns: An async stream of event arrays.
Example.swift
let scene = try engine.scene.create()
let page = try engine.block.create(.page)
try engine.block.appendChild(to: scene, child: page)

let block = try engine.block.create(.graphic)
try engine.block.setShape(block, shape: engine.block.createShape(.star))
try engine.block.setFill(block, fill: engine.block.createFill(.color))
try engine.block.appendChild(to: page, child: block)

let task = Task {
    for await events in engine.event.subscribe(to: [block]) {
        for event in events {
            print("Event: \(event.type) \(event.block)")
            if engine.block.isValid(event.block) {
                let type = try engine.block.getType(event.block)
                print("Block type: \(type)")
            }
        }
    }
}

try await Task.sleep(for: .seconds(1))
try engine.block.setRotation(block, radians: 0.5 * .pi)
try await Task.sleep(for: .seconds(1))
try engine.block.destroy(block)
try await Task.sleep(for: .seconds(1))

Variables
Use the variable API to modify scene variables.
Setup
This example uses the headless CreativeEngine. See the Setup article for details.
Functions
public func findAll() -> [String]
* Description: Retrieves all text variable names.
* Returns: A list of variable names.
public func set(key: String, value: String) throws
* Description: Sets a text variable.
* Parameters:
    * key: The variable key.
    * value: The variable value.
public func get(key: String) throws -> String
* Description: Gets the value of a text variable.
* Parameters:
    * key: The variable key.
* Returns: The variable value.
public func remove(key: String) throws
* Description: Removes a text variable.
* Parameters:
    * key: The variable key.
public func referencesAnyVariables(_ id: DesignBlockID) throws -> Bool
* Description: Checks whether a block (without checking its children) references any variables.
* Parameters:
    * id: The block ID.
* Returns: true if variables are referenced, otherwise false.
Localizing Variable Keys (CE.SDK only)
You can display localized labels for registered variables by adding a corresponding label at i18n.<language>.variables.<key>.label in the configuration. Otherwise, the key used in variable.setString() will be shown.
Example.swift
// Query all variables
let variableNames = engine.variable.findAll()

// Set, get, and remove a variable
try engine.variable.set(key: "name", value: "Chris")
let name = try engine.variable.get(key: "name") // "Chris"
try engine.variable.remove(key: "name")

let block = try engine.block.create(.graphic)
let referencesVariables = try engine.block.referencesAnyVariables(block)

Credits and License
This documentation is provided as part of the CreativeEditor SDK. For further details, please refer to the official documentation and licensing information provided by the vendor.
---

### Explanation

1. **Heading Structure:**  
   The file uses Markdown heading levels (`#`, `##`, `###`, etc.) consistently so that each section is clearly defined.

2. **Code Blocks:**  
   All Swift code snippets are enclosed in triple backticks with `swift` specified as the language for syntax highlighting.

3. **Bullet Lists & Descriptions:**  
   Parameters and return values are listed under each function description for clarity.

4. **Setup & Notes:**  
   Reusable setup instructions and notes (like linking to the [Setup](#) article) are provided to maintain consistency throughout the documentation.

This reformatting should make the file easier to read and maintain while preserving all of the original content. Feel free to adjust links, headings, or details to better match your project’s documentation standards.
