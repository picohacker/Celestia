//
//  SearchView.swift
//  Celestia
//
//  Created by Francesco on 31/05/26.
//

import SwiftUI

struct SearchView: View {
    var body: some View {
        screenBody(
            title: "Search",
            subtitle: "Find content, creators, and anything else you need."
        )
    }
}

private extension SearchView {
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
