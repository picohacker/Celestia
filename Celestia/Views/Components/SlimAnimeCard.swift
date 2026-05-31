//
//  SlimAnimeCard.swift
//  Celestia
//
//  Created by Francesco on 31/05/26.
//

import SwiftUI

struct SlimAnimeCard: View {
    private let title: String
    private let imageURL: URL?

    init(anime: AnimeSummary) {
        self.title = anime.displayTitle
        self.imageURL = anime.imageURL
    }

    init(title: String, imageURL: URL?) {
        self.title = title
        self.imageURL = imageURL
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RemoteImageView(url: imageURL)
                .frame(width: 110, height: 160)

            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 110)
    }
}
