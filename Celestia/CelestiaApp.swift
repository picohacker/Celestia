//
//  CelestiaApp.swift
//  Celestia
//
//  Created by Francesco on 31/05/26.
//

import SwiftUI

@main
struct CelestiaApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {
                HomeView()
                    .tabItem {
                        Label("Home", systemImage: "house.fill")
                    }
                
                LibraryView()
                    .tabItem {
                        Label("Library", systemImage: "books.vertical.fill")
                    }
                
                DownloadsView()
                    .tabItem {
                        Label("Downloads", systemImage: "arrow.down.circle.fill")
                    }
                
                SearchView()
                    .tabItem {
                        Label("Search", systemImage: "magnifyingglass")
                    }
            }
            .environmentObject(ModuleStore.shared)
        }
    }
}
