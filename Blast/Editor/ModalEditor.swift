import IMGLYVideoEditor
import SwiftUI

struct ModalEditor<Editor: View, Label: View>: View {
  @ViewBuilder private let editor: () -> Editor
  @ViewBuilder private let dismissLabel: () -> Label
  private let onDismiss: (() -> Void)?

  init(
    @ViewBuilder editor: @escaping () -> Editor,
    @ViewBuilder dismissLabel: @escaping () -> Label = { SwiftUI.Label("Home", systemImage: "house") },
    onDismiss: (() -> Void)? = nil
  ) {
    self.editor = editor
    self.dismissLabel = dismissLabel
    self.onDismiss = onDismiss
  }

  @State private var isBackButtonHidden = false
  @Environment(\.dismiss) private var dismiss

  @ViewBuilder private var dismissButton: some View {
    Button {
      onDismiss?()
      dismiss()
    } label: {
      dismissLabel()
    }
  }

  var body: some View {
    NavigationView {
      editor()
        .onPreferenceChange(BackButtonHiddenKey.self) { newValue in
          isBackButtonHidden = newValue
        }
        .toolbar {
          ToolbarItem(placement: .navigationBarLeading) {
            if !isBackButtonHidden {
              dismissButton
            }
          }
        }
    }
    .navigationViewStyle(.stack)
  }
}