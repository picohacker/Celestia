//
//  SettingsView.swift
//  Celestia
//
//  Created by Francesco on 31/05/26.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage(SettingsKeys.includeAdultContent) private var includeAdultContent = false
    @EnvironmentObject private var moduleStore: ModuleStore
    @State private var moduleURL = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    
    var body: some View {
        Form {
            Section(header: Text("Content"), footer: Text("When disabled, AniList results hide adult content.")) {
                Toggle("Show 18+ content", isOn: $includeAdultContent)
            }

            Section("Modules") {
                TextField("Module JSON URL", text: $moduleURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button {
                    Task { await addModule() }
                } label: {
                    if isWorking {
                        ProgressView()
                    } else {
                        Text("Download Module")
                    }
                }
                .disabled(isWorking || moduleURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if moduleStore.records.isEmpty {
                    Text("No modules added yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(moduleStore.records) { record in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.name)
                                .font(.headline)
                            Text(record.jsonURL)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete(perform: removeModules)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color("SecondaryBackgroundColor"))
        .navigationTitle("Settings")
    }
}

private extension SettingsView {
    func addModule() async {
        isWorking = true
        errorMessage = nil
        do {
            try await moduleStore.addModule(from: moduleURL)
            moduleURL = ""
        } catch {
            errorMessage = error.localizedDescription
        }
        isWorking = false
    }

    func removeModules(at offsets: IndexSet) {
        offsets.map { moduleStore.records[$0].id }.forEach(moduleStore.removeModule)
    }
}
