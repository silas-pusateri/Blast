//
//  RefreshableView.swift
//  Blast
//
//  Created by Silas Pusateri on 2/6/25.
//

import SwiftUI

// Custom RefreshableView implementation
struct RefreshableView<Content: View>: View {
    @Binding var isRefreshing: Bool
    let onRefresh: () async throws -> Void
    let content: Content
    @State private var offset: CGFloat = 0
    private let threshold: CGFloat = 50
    
    init(
        isRefreshing: Binding<Bool>,
        onRefresh: @escaping () async throws -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self._isRefreshing = isRefreshing
        self.onRefresh = onRefresh
        self.content = content()
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: OffsetPreferenceKey.self,
                    value: geometry.frame(in: .named("scrollView")).minY
                )
            }
            .frame(height: 0)
            
            content
        }
        .coordinateSpace(name: "scrollView")
        .onPreferenceChange(OffsetPreferenceKey.self) { offset in
            self.offset = offset
            
            if offset > threshold && !isRefreshing {
                isRefreshing = true
                Task {
                    try? await onRefresh()
                }
            }
        }
        .overlay(alignment: .top) {
            if isRefreshing {
                ProgressView()
                    .tint(.white)
                    .frame(height: 50)
            } else if offset > 0 {
                // Pull indicator
                Image(systemName: "arrow.down")
                    .foregroundColor(.white)
                    .frame(height: 50)
                    .opacity(Double(min(threshold > 0 ? offset / threshold : 0, 1.0)))
                    .rotationEffect(.degrees(Double(min(threshold > 0 ? (offset / threshold) * 180 : 0, 180))))
            }
        }
    }
}

// Preference key for tracking scroll offset
private struct OffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
