//
//  ModuleDetailModels.swift
//  Celestia
//
//  Created by Francesco on 31/05/26.
//

import Foundation

struct ModuleMediaDetail: Hashable {
    let title: String
    let moduleName: String
    let imageURL: URL?
    let aliases: [String]
    let synopsis: String
    let airDate: String?
    let starsText: String?
    let episodeCountText: String?
    let episodes: [ModuleMediaEpisode]
}

struct ModuleMediaEpisode: Identifiable, Hashable {
    let id: String
    let number: String
    let title: String?
    let href: String?
    let downloadURL: String?
    let imageURL: URL?

    var displayTitle: String {
        if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return title
        }
        return "Episode \(number)"
    }
}

extension ModuleMediaDetail {
    static func parse(details: Any?, episodes: Any?, fallbackItem: ModuleSearchItem) -> ModuleMediaDetail {
        let detailDictionary = ModuleJSONValue.dictionary(from: details)
        let detailPayload = ModuleJSONValue.dictionary(from: detailDictionary?["details"])
            ?? ModuleJSONValue.dictionary(from: detailDictionary?["info"])
            ?? ModuleJSONValue.dictionary(from: detailDictionary?["data"])
            ?? ModuleJSONValue.dictionary(from: detailDictionary?["result"])
            ?? detailDictionary

        let episodeArray = ModuleJSONValue.array(from: episodes)
            ?? ModuleJSONValue.array(from: detailPayload?["episodes"])
            ?? ModuleJSONValue.array(from: detailPayload?["items"])
            ?? ModuleJSONValue.array(from: detailPayload?["list"])

        let title = stringValue(from: detailPayload, keys: ["title", "name", "animeTitle", "seriesTitle"]) ?? fallbackItem.title
        let imageURL = urlValue(from: detailPayload, keys: ["image", "imageURL", "imageUrl", "poster", "posterURL", "thumbnail", "cover", "coverImage"])
            ?? fallbackItem.imageURL
        let aliases = stringArray(from: detailPayload, keys: ["aliases", "alternativeTitles", "altTitles", "synonyms"])
        let synopsis = stringValue(from: detailPayload, keys: ["synopsis", "description", "overview", "summary"])?.strippingHTMLTags()
            ?? "No synopsis available."
        let airDate = stringValue(from: detailPayload, keys: ["airDate", "aired", "releaseDate", "date"])
        let starsText = stringValue(from: detailPayload, keys: ["stars", "rating", "score"])
        let episodeCountText = stringValue(from: detailPayload, keys: ["episodes", "episodeCount", "count"])

        let episodes = episodeArray?.compactMap { ModuleMediaEpisode.parse($0) }
            .sorted { lhs, rhs in
                lhs.sortOrder < rhs.sortOrder
            } ?? []

        return ModuleMediaDetail(
            title: title,
            moduleName: fallbackItem.moduleName,
            imageURL: imageURL,
            aliases: aliases,
            synopsis: synopsis,
            airDate: airDate,
            starsText: starsText,
            episodeCountText: episodeCountText,
            episodes: episodes
        )
    }
}

private extension ModuleMediaEpisode {
    var sortOrder: Int {
        Int(number.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)) ?? Int.max
    }

    static func parse(_ payload: Any) -> ModuleMediaEpisode? {
        guard let dict = ModuleJSONValue.dictionary(from: payload) else { return nil }

        let number = stringValue(from: dict, keys: ["number", "episode", "episodeNumber", "index", "id"]) ?? "0"
        let title = stringValue(from: dict, keys: ["title", "name", "label"])
        let href = stringValue(from: dict, keys: ["href", "url", "link"])
        let downloadURL = stringValue(from: dict, keys: ["downloadUrl", "downloadURL", "streamUrl", "videoUrl"])
        let imageURL = urlValue(from: dict, keys: ["image", "imageURL", "imageUrl", "poster", "thumbnail", "cover"])

        let identifier = stringValue(from: dict, keys: ["id", "href", "url", "link"])
            ?? [number, title ?? "episode"].joined(separator: "-")

        return ModuleMediaEpisode(
            id: identifier,
            number: number,
            title: title,
            href: href,
            downloadURL: downloadURL,
            imageURL: imageURL
        )
    }
}

private enum ModuleJSONValue {
    static func dictionary(from value: Any?) -> [String: Any]? {
        if let dict = value as? [String: Any] {
            return dict
        }

        if let dict = value as? [AnyHashable: Any] {
            return dict.reduce(into: [:]) { result, entry in
                result[String(describing: entry.key)] = entry.value
            }
        }

        if let array = value as? [Any] {
            return array.compactMap { dictionary(from: $0) }.first
        }

        if let string = value as? String,
           let data = string.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) {
            return dictionary(from: json)
        }

        return nil
    }

    static func array(from value: Any?) -> [Any]? {
        if let array = value as? [Any] {
            return array
        }

        if let string = value as? String,
           let data = string.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) {
            return json as? [Any]
        }

        if let dict = dictionary(from: value) {
            if let nested = dict["episodes"] as? [Any] {
                return nested
            }
            if let nested = dict["items"] as? [Any] {
                return nested
            }
            if let nested = dict["list"] as? [Any] {
                return nested
            }
        }

        return nil
    }
}

private func stringValue(from dict: [String: Any]?, keys: [String]) -> String? {
    guard let dict else { return nil }

    for key in keys {
        if let value = dict[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return value
        }

        if let value = dict[key] as? NSNumber {
            return value.stringValue
        }

        if let value = dict[key] as? [String: Any],
           let nested = stringValue(from: value, keys: ["en", "english", "romaji", "native", "userPreferred", "title", "name"]) {
            return nested
        }
    }

    return nil
}

private func stringArray(from dict: [String: Any]?, keys: [String]) -> [String] {
    guard let dict else { return [] }

    for key in keys {
        if let value = dict[key] as? [String] {
            return value.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }

        if let value = dict[key] as? [Any] {
            let strings = value.compactMap { element -> String? in
                if let string = element as? String { return string }
                if let number = element as? NSNumber { return number.stringValue }
                if let nested = element as? [String: Any] {
                    return stringValue(from: nested, keys: ["title", "name", "value"])
                }
                return nil
            }
            if !strings.isEmpty {
                return strings
            }
        }

        if let value = dict[key] as? String,
           !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return value
                .components(separatedBy: CharacterSet(charactersIn: ",;/|"))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
    }

    return []
}

private func urlValue(from dict: [String: Any]?, keys: [String]) -> URL? {
    guard let dict else { return nil }

    for key in keys {
        if let string = dict[key] as? String, let url = URL(string: string) {
            return url
        }

        if let nested = dict[key] as? [String: Any],
           let string = stringValue(from: nested, keys: ["large", "extraLarge", "medium", "small", "url", "image", "cover", "poster"]),
           let url = URL(string: string) {
            return url
        }
    }

    return nil
}

private extension String {
    func strippingHTMLTags() -> String {
        var result = self
        let replacements = ["<br>", "<br/>", "<br />", "<i>", "</i>", "<I>", "</I>", "<b>", "</b>", "<B>", "</B>"]
        replacements.forEach { result = result.replacingOccurrences(of: $0, with: "") }
        return result
    }
}