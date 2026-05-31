//
//  LibraryView.swift
//  Celestia
//
//  Created by Francesco on 31/05/26.
//

import SwiftUI

struct LibraryView: View {
    var body: some View {
        screenBody(
            title: "Library",
            subtitle: "Browse your saved items, collections, and history."
        )
    }
}


private extension LibraryView {
    func screenBody(title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.largeTitle.bold())
            Text(subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
