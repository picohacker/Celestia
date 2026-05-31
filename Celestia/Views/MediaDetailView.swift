//
//  MediaDetailView.swift
//  Celestia
//
//  Created by Francesco on 31/05/26.
//

import SwiftUI

private enum MediaDetailLoadState {
    case idle
    case loading
    case loaded(ModuleMediaDetail)
    case failed(String)
}

struct MediaDetailView: View {
    @EnvironmentObject private var moduleStore: ModuleStore
    
    let item: ModuleSearchItem
    
    @State private var loadState: MediaDetailLoadState = .idle
    @State private var isSynopsisExpanded = false
    @State private var isFavorite = false
    @State private var episodeRange: ClosedRange<Int> = 0...99
    @State private var selectedRange = "1-100"
    
    var body: some View {
        Group {
            switch loadState {
            case .idle, .loading:
                loadingView
            case .failed(let message):
                errorView(message)
            case .loaded(let detail):
                mediaDetailContent(detail)
            }
        }
        .background(backgroundColor.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadDetail() }
    }
}

private extension MediaDetailView {
    func mediaDetailContent(_ detail: ModuleMediaDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                headerRow(detail)

                if !detail.synopsis.isEmpty {
                    synopsisRow(detail)
                }

                actionRow

                episodesSection(detail)
            }
            .padding(16)
        }
    }
    
    func headerRow(_ detail: ModuleMediaDetail) -> some View {
        HStack(alignment: .top, spacing: 10) {
            RemoteImageView(url: detail.imageURL, cornerRadius: 10)
                .frame(width: 110, height: 160)

            VStack(alignment: .leading, spacing: 4) {
                Text(detail.title)
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(4)

                if !detail.aliases.isEmpty {
                    Text(detail.aliases.joined(separator: " • "))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 6)

                HStack(spacing: 12) {
                    Button { } label: {
                        Image(systemName: "ellipsis.circle")
                            .resizable()
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)

                    Button { } label: {
                        Image(systemName: "safari")
                            .resizable()
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    func synopsisRow(_ detail: ModuleMediaDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            
            HStack(spacing: 4) {
                Text("Synopsis")
                    .font(.system(size: 16, weight: .bold))

                Spacer()

                if shouldShowSynopsisToggle(detail.synopsis) {
                    Button(isSynopsisExpanded ? "Less" : "More") {
                        isSynopsisExpanded.toggle()
                    }
                    .font(.system(size: 14))
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                }
            }

            Text(detail.synopsis)
                .lineLimit(isSynopsisExpanded ? nil : 4)
                .font(.system(size: 14))
                .foregroundStyle(.primary)
        }
    }

    var actionRow: some View {
        HStack(spacing: 12) {
            Button { } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                    Text("Start Watching")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.accentColor)
                .cornerRadius(10)
            }
            .buttonStyle(.plain)

            Button {
                isFavorite.toggle()
            } label: {
                Image(systemName: isFavorite ? "bookmark.fill" : "bookmark")
                    .resizable()
                    .frame(width: 20, height: 27)
            }
            .buttonStyle(.plain)
        }
    }

    func episodesSection(_ detail: ModuleMediaDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            
            HStack {
                if detail.episodes.count > 100 {
                    Menu {
                        ForEach(episodeRanges(total: detail.episodes.count), id: \.label) { range in
                            Button(range.label) {
                                episodeRange = range.range
                                selectedRange = range.label
                            }
                        }
                    } label: {
                        Text(selectedRange)
                            .font(.system(size: 14))
                    }
                }
            }

            if detail.episodes.isEmpty {
                Text("No episodes available for this result.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(clampedRange(total: detail.episodes.count), id: \.self) { index in
                    let episode = detail.episodes[index]
                    let episodeImageURL = episode.imageURL ?? detail.imageURL
                    episodeRow(episode, index: index, imageURL: episodeImageURL)
                }
            }
        }
        .onAppear { resetEpisodeRangeIfNeeded(total: detail.episodes.count) }
        .onChange(of: detail.episodes.count) { newValue in
            resetEpisodeRangeIfNeeded(total: newValue)
        }
    }

    func episodeRow(_ episode: ModuleMediaEpisode, index: Int, imageURL: URL?) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Text("Episode \(index + 1)")
                        .font(.system(size: 15))

                    Button { } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                }

                Spacer()

                Button { } label: {
                    Image(systemName: "icloud.and.arrow.down")
                        .font(.system(size: 18))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
            }

            HStack(spacing: 8) {
                ProgressView(value: 0.0)
                    .tint(.accentColor)
                    .frame(width: 140)

                Text("Start Watching")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                Spacer()

                Text("00:00 left")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    var loadingView: some View {
        ProgressView()
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func errorView(_ message: String) -> some View {
        VStack(spacing: 8) {
            Text("Unable to load details")
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    var backgroundColor: Color {
        Color("SecondaryBackgroundColor")
    }

    func progressRing(progress: Double) -> some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.3), lineWidth: 4)
            Circle()
                .trim(from: 0, to: max(0.02, min(1.0, progress)))
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }

    func episodeRanges(total: Int) -> [(label: String, range: ClosedRange<Int>)] {
        guard total > 0 else { return [] }
        let chunkSize = 100
        let chunkCount = (total + chunkSize - 1) / chunkSize

        return (0..<chunkCount).map { index in
            let start = index * chunkSize
            let end = min((index + 1) * chunkSize - 1, total - 1)
            let label = "\(start + 1)-\(end + 1)"
            return (label: label, range: start...end)
        }
    }

    func clampedRange(total: Int) -> ClosedRange<Int> {
        guard total > 0 else { return 0...0 }
        let lower = max(0, min(episodeRange.lowerBound, total - 1))
        let upper = max(lower, min(episodeRange.upperBound, total - 1))
        return lower...upper
    }

    func resetEpisodeRangeIfNeeded(total: Int) {
        guard total > 0 else { return }
        let upper = min(99, total - 1)
        if episodeRange.lowerBound != 0 || episodeRange.upperBound != upper {
            episodeRange = 0...upper
            selectedRange = "1-\(upper + 1)"
        }
    }
    
    func shouldShowSynopsisToggle(_ synopsis: String) -> Bool {
        synopsis.count > 180
    }
    
    func loadDetail() async {
        if case .loading = loadState { return }
        if case .loaded = loadState { return }
        
        loadState = .loading
        
        do {
            let detail = try await moduleStore.fetchMediaDetail(for: item)
            loadState = .loaded(detail)
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }
}
