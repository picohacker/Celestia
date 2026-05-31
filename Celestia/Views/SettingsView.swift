//
//  SettingsView.swift
//  Celestia
//
//  Created by Francesco on 31/05/26.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage(SettingsKeys.includeAdultContent) private var includeAdultContent = false
    
    var body: some View {
        Form {
            Section(header: Text("Content"), footer: Text("When disabled, AniList results hide adult content.")) {
                Toggle("Show 18+ content", isOn: $includeAdultContent)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color("SecondaryBackgroundColor"))
        .navigationTitle("Settings")
    }
}
