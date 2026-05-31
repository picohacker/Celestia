//
//  DownloadsView.swift
//  Celestia
//
//  Created by Francesco on 31/05/26.
//

import SwiftUI

struct DownloadsView: View {
    var body: some View {
        screenBody(
            title: "Downloads",
            subtitle: "Track offline content and completed transfers."
        )
    }
}

private extension DownloadsView {
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
        .background(Color("SecondaryBackgroundColor"))
    }
}
