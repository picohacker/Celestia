//
//  SlimAnimeCard.swift
//  Celestia
//
//  Created by Francesco on 31/05/26.
//

import SwiftUI

struct SlimAnimeCard: View {
    let anime: AnimeSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RemoteImageView(url: anime.imageURL)
                .frame(width: 110, height: 160)

            Text(anime.displayTitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 110)
    }
}
