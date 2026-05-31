//
//  AiringAnimeCard.swift
//  Celestia
//
//  Created by Francesco on 31/05/26.
//

import SwiftUI

struct AiringAnimeCard: View {
    let anime: AnimeSummary
    
    private let imageWidth: CGFloat = 96
    private let imageHeight: CGFloat = 144
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack(alignment: .bottom) {
                RemoteImageView(url: anime.imageURL)
                    .frame(width: imageWidth, height: imageHeight)
                
                if let episodesText = episodesText {
                    Text(episodesText)
                        .font(.system(size: 12))
                        .frame(width: imageWidth * 0.8)
                        .padding(.vertical, 3)
                        .multilineTextAlignment(.center)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .padding(6)
                }
            }
            .frame(width: imageWidth, height: imageHeight)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            
            VStack(alignment: .leading, spacing: 6) {
                if let airingText = airingTimeText {
                    Text(airingText)
                        .foregroundStyle(.accent)
                        .font(.system(size: 12, weight: .semibold))
                }
                
                Text(anime.displayTitle)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                
                Text(descriptionText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(5)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    
    private var episodesText: String? {
        guard let episodes = anime.episodes else {
            return "Ep. N/A"
        }
        return "Ep. \(episodes)"
    }
    
    private var descriptionText: String {
        let text = anime.description?.strippingHTMLTags() ?? "Description not available"
        return text.isEmpty ? "Description not available" : text
    }
    
    private var airingTimeText: String? {
        guard let airingAt = anime.airingAt else {
            return nil
        }
        
        let date = Date(timeIntervalSince1970: TimeInterval(airingAt))
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)
        let airingDay = calendar.startOfDay(for: date)
        
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm zzz"
        timeFormatter.timeZone = .current
        timeFormatter.locale = .current
        
        if airingDay == today {
            return "Today, \(timeFormatter.string(from: date))"
        }
        
        if let tomorrow, airingDay == tomorrow {
            return "Tomorrow, \(timeFormatter.string(from: date))"
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEEE, HH:mm zzz"
        dateFormatter.timeZone = .current
        dateFormatter.locale = .current
        return dateFormatter.string(from: date)
    }
}

private extension String {
    func strippingHTMLTags() -> String {
        var result = self
        let replacements = [
            "<br>", "<br/>", "<br />", "<i>",
            "</i>", "<I>", "</I>", "<b>",
            "</b>", "<B>", "</B>"
        ]
        replacements.forEach { result = result.replacingOccurrences(of: $0, with: "") }
        return result
    }
}
