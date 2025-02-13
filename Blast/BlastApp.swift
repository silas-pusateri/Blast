//
//  BlastApp.swift
//  Blast
//
//  Created by Silas Pusateri on 2/3/25.
//

import SwiftUI
import FirebaseCore

class OrientationLock {
    static func lock(to orientation: UIInterfaceOrientationMask) {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: orientation))
        }
        AppDelegate.orientationLock = orientation
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientationLock = UIInterfaceOrientationMask.portrait
    
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return AppDelegate.orientationLock
    }
}

@main
struct BlastApp: App {
    @StateObject private var authState = AuthenticationState()
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    init() {
        FirebaseApp.configure()
        // Lock orientation to portrait
        OrientationLock.lock(to: .portrait)
    }
    
    var body: some Scene {
        WindowGroup {
            SplashScreenView()
                .environmentObject(authState)
                .edgesIgnoringSafeArea(.all)
        }
    }
}
