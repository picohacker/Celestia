//
//  HomeView.swift
//  Celestia
//
//  Created by Francesco on 31/05/26.
//

import SwiftUI

struct HomeView: View {
    @State private var loadState: LoadState = .idle
    @State private var airingAnime: [AnimeSummary] = []
    @State private var trendingAnime: [AnimeSummary] = []
    @State private var seasonalAnime: [AnimeSummary] = []
    @State private var isShowingSettings = false
    
    private let service = AniListService.shared
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if case let .failed(message) = loadState {
                        Text(message)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    
                    Divider()
                    HStack(alignment: .bottom, spacing: 5) {
                        Text("Airing")
                            .fontWeight(.bold)
                            .font(.system(size: 20))
                        
                        Text("This Week")
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)
                    }
                    
                    if airingAnime.isEmpty {
                        loadingRow
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .top, spacing: 16) {
                                ForEach(airingAnime) { anime in
                                    AiringAnimeCard(anime: anime)
                                        .frame(width: 300, alignment: .leading)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    
                    Divider()
                    HStack(alignment: .bottom, spacing: 5) {
                        Text("Trending")
                            .fontWeight(.bold)
                            .font(.system(size: 20))
                        
                        Text("on " + currentDayLabel)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)
                    }
                    horizontalStrip(items: trendingAnime)
                    
                    Divider()
                    HStack(alignment: .bottom, spacing: 5) {
                        Text("Seasonal")
                            .fontWeight(.bold)
                            .font(.system(size: 20))
                        
                        Text(currentSeasonLabel)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)
                    }
                    horizontalStrip(items: seasonalAnime)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
            .navigationTitle("Home")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .background(Color("SecondaryBackgroundColor"))
            .sheet(isPresented: $isShowingSettings) {
                NavigationStack {
                    SettingsView()
                }
            }
            .task {
                await loadData()
            }
            .refreshable {
                await loadData()
            }
        }
    }
    
    private var loadingRow: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text("Loading...")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func horizontalStrip(items: [AnimeSummary]) -> some View {
        Group {
            if items.isEmpty {
                loadingRow
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 16) {
                        ForEach(items) { anime in
                            SlimAnimeCard(anime: anime)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
    
    private var currentDayLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, dd MMMM yyyy"
        formatter.locale = .current
        return formatter.string(from: Date())
    }
    
    private var currentSeasonLabel: String {
        let month = Calendar.current.component(.month, from: Date())
        let year = Calendar.current.component(.year, from: Date())
        
        let season: String
        switch month {
        case 12, 1, 2:
            season = "Winter"
        case 3, 4, 5:
            season = "Spring"
        case 6, 7, 8:
            season = "Summer"
        default:
            season = "Fall"
        }
        
        return "of \(season), \(year)"
    }
    
    @MainActor
    private func loadData() async {
        loadState = .loading
        do {
            async let airing = service.fetchAiringAnime()
            async let trending = service.fetchTrendingAnime()
            async let seasonal = service.fetchSeasonalAnime()
            
            let (airingResult, trendingResult, seasonalResult) = try await (airing, trending, seasonal)
            airingAnime = airingResult
            trendingAnime = trendingResult
            seasonalAnime = seasonalResult
            loadState = .idle
        } catch {
            loadState = .failed("Failed to load AniList data. Please try again.")
        }
    }
}

private enum LoadState {
    case idle
    case loading
    case failed(String)
}
