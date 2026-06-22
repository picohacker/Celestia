//
//  MediaDetailView.swift
//  Celestia
//
//  Created by Francesco on 31/05/26.
//

import Sybau
import SwiftUI
import Kingfisher

private enum MediaDetailLoadState {
    case idle
    case loading
    case loaded(ModuleMediaDetail)
    case failed(String)
}

struct StreamResponse: Decodable {
    let streamUrl: String?
    let subtitle: String?
    let subtitles: String?
    let streams: [StreamServer]?
}

struct StreamServer: Decodable, Identifiable {
    var id: String { title }
    
    let title: String
    let streamUrl: String
    let headers: [String: String]?
}

struct MediaDetailView: View {
    @EnvironmentObject private var moduleStore: ModuleStore
    
    let item: ModuleSearchItem
    
    @State private var loadState: MediaDetailLoadState = .idle
    @State private var isSynopsisExpanded = false
    @State private var isFavorite = false
    @State private var episodeRange: ClosedRange<Int> = 0...99
    @State private var selectedRange = "1-100"
    @State private var episodeImages: [Int: URL] = [:]
    @State private var isFetchingEpisodeImages: Bool = false
    @State private var episodeTitles: [Int: String] = [:]
    @State private var streamSources: [[String: Any]]? = nil
    @State private var streamURLs: [String]? = nil
    @State private var subtitleURLs: [String]? = nil
    @State private var isFetchingStream: Bool = false
    @State private var streamError: String? = nil
    @State private var selectedEpisodeHref: String? = nil
    
    @State private var selectedStreamURL: URL?
    @State private var selectedSubtitleURL: URL?
    @State private var availableStreams: [StreamServer] = []
    @State private var selectedHeaders: [String: String] = [:]
    
    @State private var showStreamPicker = false
    
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
        .confirmationDialog(
            "Select Stream",
            isPresented: $showStreamPicker
        ) {
            ForEach(availableStreams) { stream in
                Button(stream.title) {
                    playStream(
                        url: stream.streamUrl,
                        headers: stream.headers ?? [:],
                        subtitle: selectedSubtitleURL?.absoluteString
                    )
                }
            }
        }
    }
}

private extension MediaDetailView {
    func mediaDetailContent(_ detail: ModuleMediaDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                headerRow(detail)
                
                if hasMetadata(detail) {
                    metadataRow(detail)
                }
                
                if !detail.synopsis.isEmpty {
                    synopsisRow(detail)
                }
                
                actionRow
                
                episodesSection(detail)
            }
            .padding(16)
        }
    }
    
    // MARK: - Header
    
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
    
    func metadataRow(_ detail: ModuleMediaDetail) -> some View {
        HStack(spacing: 16) {
            if let airDate = detail.airDate, !airDate.isEmpty {
                Label(airDate, systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            if let episodeCountText = detail.episodeCountText, !episodeCountText.isEmpty {
                Label("\(episodeCountText) eps", systemImage: "list.bullet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
    
    func hasMetadata(_ detail: ModuleMediaDetail) -> Bool {
        return (detail.airDate?.isEmpty == false) ||
        (detail.episodeCountText?.isEmpty == false)
    }
    
    // MARK: - Synopsis
    
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
    
    // MARK: - Actions
    
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
    
    // MARK: - Episodes
    
    func episodesSection(_ detail: ModuleMediaDetail) -> some View {
        VStack(alignment: .leading, spacing: 6) {
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
                let visibleRange = clampedRange(total: detail.episodes.count)
                ForEach(visibleRange, id: \.self) { index in
                    let episode = detail.episodes[index]
                    let episodeImageURL = episode.imageURL ?? episodeImages[index] ?? detail.imageURL
                    VStack(spacing: 0) {
                        episodeRow(episode, index: index, imageURL: episodeImageURL)
                        if index < visibleRange.upperBound {
                            Divider()
                                .padding(.leading, 116)
                        }
                    }
                }
            }
        }
        .onAppear { resetEpisodeRangeIfNeeded(total: detail.episodes.count) }
        .onChange(of: detail.episodes.count) { newValue in
            resetEpisodeRangeIfNeeded(total: newValue)
        }
    }
    
    func episodeRow(_ episode: ModuleMediaEpisode, index: Int, imageURL: URL?) -> some View {
        let fullURLCandidate = episode.href ?? episode.downloadURL
        let progress: Double = {
            guard let full = fullURLCandidate else { return 0.0 }
            let last = UserDefaults.standard.double(forKey: "lastPlayedTime_\(full)")
            let total = UserDefaults.standard.double(forKey: "totalTime_\(full)")
            return total > 0 ? min(max(last / total, 0.0), 1.0) : 0.0
        }()
        
        let isSelected = selectedEpisodeHref != nil && selectedEpisodeHref == fullURLCandidate
        let isLoadingThis = isSelected && isFetchingStream
        
        return VStack(spacing: 8) {
            HStack(spacing: 12) {
                KFImage(imageURL ?? URL(string: "https://raw.githubusercontent.com/cranci1/Celestia/refs/heads/main/assets/banner.jpg"))
                    .resizable()
                    .aspectRatio(16/9, contentMode: .fill)
                    .frame(width: 100, height: 56)
                    .cornerRadius(8)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Episode \(index + 1)")
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    
                    let mappedTitle = episodeTitles[index]
                    if let mapped = mappedTitle, !mapped.isEmpty {
                        Text(mapped)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else if let epTitle = episode.title, !epTitle.isEmpty {
                        Text(epTitle)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text(episode.displayTitle)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                if isLoadingThis {
                    ProgressView()
                        .frame(width: 40, height: 40)
                } else {
                    CircularProgressBar(progress: progress)
                        .frame(width: 40, height: 40)
                }
            }
            .contentShape(Rectangle())
            .padding(.vertical, 6)
            .onTapGesture {
                guard !isFetchingStream else { return }
                guard let detail = loadedDetail else { return }
                fetchStream(for: episode, moduleName: detail.moduleName)
            }
            
            if isSelected, let error = streamError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }
        }
    }
    
    // MARK: - Helpers
    
    private var loadedDetail: ModuleMediaDetail? {
        if case .loaded(let d) = loadState { return d }
        return nil
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
    
    // MARK: - Fetching
    
    func fetchStream(for episode: ModuleMediaEpisode, moduleName: String) {
        guard let href = episode.href ?? episode.downloadURL, !href.isEmpty else {
            streamError = "No stream URL available for this episode."
            return
        }
        
        isFetchingStream = true
        selectedEpisodeHref = href
        streamError = nil
        streamURLs = nil
        streamSources = nil
        subtitleURLs = nil
        
        Task {
            let result = await moduleStore.fetchStreamUrl(for: episode, moduleName: moduleName)
            isFetchingStream = false
            
            streamSources = result.sources
            streamURLs = result.streams
            
            if let subs = result.subtitles {
                subtitleURLs = subs
            }
            
            handleFetchedStreams(
                sources: result.sources,
                urls: result.streams
            )
        }
    }
    
    func loadDetail() async {
        if case .loading = loadState { return }
        if case .loaded = loadState { return }
        
        loadState = .loading
        
        do {
            let detail = try await moduleStore.fetchMediaDetail(for: item)
            loadState = .loaded(detail)
            Task { await fetchEpisodeImages(for: detail) }
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }
    
    func fetchEpisodeImages(for detail: ModuleMediaDetail) async {
        guard !isFetchingEpisodeImages else { return }
        isFetchingEpisodeImages = true
        
        defer { isFetchingEpisodeImages = false }
        
        do {
            let anilistID = try await AniListService.shared.fetchID(byTitle: detail.title)
            let cacheKey = "ani_mappings_\(anilistID)"
            
            if let cached = UserDefaults.standard.data(forKey: cacheKey),
               let json = try? JSONSerialization.jsonObject(with: cached) as? [String: Any] {
                applyMappings(json: json, detail: detail)
                return
            }
            
            guard let url = URL(string: "https://api.ani.zip/mappings?anilist_id=\(anilistID)") else { return }
            
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            
            let (data, _) = try await URLSession.custom.data(for: request)
            UserDefaults.standard.set(data, forKey: cacheKey)
            
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                applyMappings(json: json, detail: detail)
            }
        } catch {
            return
        }
    }
    
    func applyMappings(json: [String: Any], detail: ModuleMediaDetail) {
        guard let episodesDict = json["episodes"] as? [String: Any] else { return }
        
        var updated: [Int: URL] = [:]
        var updatedTitles: [Int: String] = [:]
        
        for (index, episode) in detail.episodes.enumerated() {
            let key = String(Int((episode.number.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression))) ?? (index + 1))
            
            if let info = episodesDict[key] as? [String: Any] {
                if let image = info["image"] as? String, let url = URL(string: image) {
                    updated[index] = url
                }
                
                if let rawTitle = info["title"] {
                    if let titleStr = rawTitle as? String, !titleStr.isEmpty {
                        updatedTitles[index] = titleStr
                    } else if let titleDict = rawTitle as? [String: Any] {
                        if let en = titleDict["en"] as? String, !en.isEmpty {
                            updatedTitles[index] = en
                        } else if let english = titleDict["english"] as? String, !english.isEmpty {
                            updatedTitles[index] = english
                        } else if let romaji = titleDict["romaji"] as? String, !romaji.isEmpty {
                            updatedTitles[index] = romaji
                        } else if let up = titleDict["userPreferred"] as? String, !up.isEmpty {
                            updatedTitles[index] = up
                        }
                    }
                }
            }
        }
        
        DispatchQueue.main.async {
            if !updated.isEmpty {
                self.episodeImages = updated
            }
            if !updatedTitles.isEmpty {
                var merged = self.episodeTitles
                for (k, v) in updatedTitles { merged[k] = v }
                self.episodeTitles = merged
            }
        }
    }
    
    // MARK: - MPV
    
    func playStream(url: String, headers: [String: String] = [:], subtitle: String? = nil) {
        guard let streamURL = URL(string: url) else { return }
        
        let preset = PlayerPreset.presets.first
        let subtitleArray: [String]? = subtitle.map { [$0] }
        let pvc = PlayerViewController(
            url: streamURL,
            preset: preset ?? PlayerPreset(title: "Default", summary: "", stream: nil, commands: []),
            headers: headers,
            subtitles: subtitleArray
        )
        pvc.modalPresentationStyle = .fullScreen
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.topmostViewController().present(pvc, animated: true, completion: nil)
        } else {
            Logger.shared.log("Failed to find root view controller to present MPV player", type: "Error")
        }
    }
    
    @MainActor
    func handleFetchedStreams(sources: [[String: Any]]?, urls: [String]?) {
        streamError = nil
        availableStreams = []
        
        if let sources = sources, !sources.isEmpty {
            let streams: [StreamServer] = sources.compactMap { source in
                guard let url = source["streamUrl"] as? String,
                      !url.isEmpty else { return nil }
                
                let title = source["title"] as? String ?? source["label"] as? String ?? "Stream"
                let headers = source["headers"] as? [String: String]
                
                return StreamServer(
                    title: title,
                    streamUrl: url,
                    headers: headers
                )
            }
            
            guard !streams.isEmpty else {
                streamError = "No valid streams found."
                return
            }
            availableStreams = streams
            
            if streams.count == 1 {
                playStream(
                    url: streams[0].streamUrl,
                    headers: streams[0].headers ?? [:],
                    subtitle: selectedSubtitleURL?.absoluteString
                )
            } else {
                showStreamPicker = true
            }
            return
        }
        
        if let urls = urls, !urls.isEmpty {
            let streams: [StreamServer] = urls.enumerated().map {
                StreamServer(
                    title: "Stream \($0.offset + 1)",
                    streamUrl: $0.element,
                    headers: nil
                )
            }
            availableStreams = streams
            
            if streams.count == 1 {
                playStream(
                    url: streams[0].streamUrl,
                    headers: [:],
                    subtitle: selectedSubtitleURL?.absoluteString
                )
            } else {
                showStreamPicker = true
            }
            return
        }
        
        streamError = "No stream found for this episode."
    }
}

extension UIViewController {
    func topmostViewController() -> UIViewController {
        if let presented = self.presentedViewController {
            return presented.topmostViewController()
        }
        
        if let navigation = self as? UINavigationController {
            return navigation.visibleViewController?.topmostViewController() ?? navigation
        }
        
        if let tabBar = self as? UITabBarController {
            return tabBar.selectedViewController?.topmostViewController() ?? tabBar
        }
        
        return self
    }
}
