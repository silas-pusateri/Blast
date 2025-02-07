import SwiftUI
import FirebaseAuth

class AuthenticationState: ObservableObject {
    @Published var isSignedIn: Bool = false
    private var handle: AuthStateDidChangeListenerHandle?
    
    init() {
        handle = Auth.auth().addStateDidChangeListener { _, user in
            self.isSignedIn = user != nil
        }
    }
    
    deinit {
        if let handle = handle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }
} 