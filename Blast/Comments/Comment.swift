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
    let parentCommentId: String?
    
    init(id: String = UUID().uuidString,
         videoId: String,
         userId: String,
         text: String,
         timestamp: Date = Date(),
         likes: Int = 0,
         parentCommentId: String? = nil) {
        self.id = id
        self.videoId = videoId
        self.userId = userId
        self.text = text
        self.timestamp = timestamp
        self.likes = likes
        self.parentCommentId = parentCommentId
    }
    
    init?(document: QueryDocumentSnapshot) {
        let data = document.data()
        
        guard let videoId = data["videoId"] as? String,
              let userId = data["userId"] as? String,
              let text = data["text"] as? String,
              let timestamp = (data["timestamp"] as? Timestamp)?.dateValue() else {
            return nil
        }
        
        self.id = document.documentID
        self.videoId = videoId
        self.userId = userId
        self.text = text
        self.timestamp = timestamp
        self.likes = data["likes"] as? Int ?? 0
        self.parentCommentId = data["parentCommentId"] as? String
    }
}
