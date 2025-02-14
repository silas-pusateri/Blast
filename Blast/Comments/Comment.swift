//
//  Comment.swift
//  Blast
//
//  Created by Silas Pusateri on 2/6/25.
//

import Foundation
import FirebaseFirestore
import SwiftUI

// Comment model
struct Comment: Identifiable {
    let id: String
    let videoId: String
    let userId: String
    let text: String
    let timestamp: Date
    var likes: Int
    
    init(id: String = UUID().uuidString,
         videoId: String,
         userId: String,
         text: String,
         timestamp: Date = Date(),
         likes: Int = 0) {
        self.id = id
        self.videoId = videoId
        self.userId = userId
        self.text = text
        self.timestamp = timestamp
        self.likes = likes
    }
    
    init?(document: QueryDocumentSnapshot) {
        let data = document.data()
        print("Parsing comment document: \(document.documentID)")  // Debug print
        print("Document data: \(data)")  // Debug print
        
        guard let userId = data["userId"] as? String,
              let text = data["text"] as? String,
              let timestamp = (data["timestamp"] as? Timestamp)?.dateValue() else {
            print("Failed to parse required fields:")  // Debug print
            if data["userId"] as? String == nil { print("- userId is nil or not a String") }
            if data["text"] as? String == nil { print("- text is nil or not a String") }
            if (data["timestamp"] as? Timestamp)?.dateValue() == nil { print("- timestamp is nil or invalid") }
            return nil
        }
        
        self.id = document.documentID
        self.videoId = data["videoId"] as? String ?? ""  // Optional for replies in subcollection
        self.userId = userId
        self.text = text
        self.timestamp = timestamp
        self.likes = data["likes"] as? Int ?? 0
    }
}
