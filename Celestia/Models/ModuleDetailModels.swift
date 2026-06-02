//
//  ModuleDetailModels.swift
//  Celestia
//
//  Created by Francesco on 31/05/26.
//

import Foundation

struct ModuleMediaEpisode: Identifiable {
    let id = UUID()
    let number: String
    let title: String?
    let href: String?
    let downloadURL: String?
    let imageURL: URL?

    var displayTitle: String {
        title ?? "Episode \(number)"
    }
}

struct ModuleMediaDetail {
    let moduleName: String
    let title: String
    let imageURL: URL?
    let synopsis: String
    let aliases: [String]
    let airDate: String?
    let episodeCountText: String?
    let episodes: [ModuleMediaEpisode]

    static func parse(
        details: [MediaItem],
        episodes: [EpisodeLink],
        fallbackItem: ModuleSearchItem
    ) -> ModuleMediaDetail {
        let detail = details.first

        let synopsis = detail?.description ?? ""

        let aliases: [String] = {
            guard let raw = detail?.aliases, !raw.isEmpty else { return [] }
            return raw
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }()

        let airDate = detail?.airdate.isEmpty == false ? detail?.airdate : nil

        let mappedEpisodes = episodes.map { link in
            ModuleMediaEpisode(
                number: String(link.number),
                title: link.title.isEmpty ? nil : link.title,
                href: link.href.isEmpty ? nil : link.href,
                downloadURL: nil,
                imageURL: nil
            )
        }

        let episodeCountText: String? = mappedEpisodes.isEmpty ? nil : String(mappedEpisodes.count)

        return ModuleMediaDetail(
            moduleName: fallbackItem.moduleName,
            title: fallbackItem.title,
            imageURL: fallbackItem.imageURL,
            synopsis: synopsis,
            aliases: aliases,
            airDate: airDate,
            episodeCountText: episodeCountText,
            episodes: mappedEpisodes
        )
    }
}
