//
//  BlastApp.swift
//  Blast
//
//  Created by Silas Pusateri on 2/3/25.
//

import SwiftUI
import FirebaseCore

@main
struct BlastApp: App {
    @StateObject private var authState = AuthenticationState()
    
    init() {
        FirebaseApp.configure()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authState)
        }
    }
}
