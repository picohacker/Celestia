//
//  SearchView.swift
//  Celestia
//
//  Created by Francesco on 31/05/26.
//

import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var moduleStore: ModuleStore
    @AppStorage("searchHistory") private var storedHistoryData = Data()
    @AppStorage("selectedModuleId") private var selectedModuleId = ""
    @State private var searchQuery = ""
    @State private var searchHistory: [String] = []
    @State private var isShowingResults = false
    @State private var activeQuery = ""

    var body: some View {
        NavigationStack {
            List {
                searchFieldSection
                historySection
            }
            .scrollContentBackground(.hidden)
            .background(backgroundColor)
            .navigationTitle("Search")
            .toolbar { modulePickerButton }
            .navigationDestination(isPresented: $isShowingResults) {
                SearchResultsView(selectedModuleId: $selectedModuleId, query: activeQuery)
                    .environmentObject(moduleStore)
            }
            .onAppear(perform: loadHistory)
        }
        .background(backgroundColor)
    }
}

private extension SearchView {
    var searchFieldSection: some View {
        Section {
            TextField("Search", text: $searchQuery)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { performSearch() }
        }
    }

    var historySection: some View {
        Section("History") {
            if searchHistory.isEmpty {
                Text("No recent searches.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(searchHistory, id: \.self) { query in
                    historyRow(for: query)
                }
            }
        }
    }

    func historyRow(for query: String) -> some View {
        HStack {
            Text(query)
            Spacer()
            Button {
                deleteHistoryItem(query)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            searchQuery = query
            performSearch()
        }
    }

    var modulePickerButton: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("All Modules") { selectModule(id: "") }
                ForEach(moduleStore.records) { record in
                    Button(record.name) { selectModule(id: record.id) }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(selectedModuleName)
                    Image(systemName: "chevron.down")
                }
                .font(.subheadline)
            }
        }
    }
}

private extension SearchView {
    var backgroundColor: Color {
        Color("SecondaryBackgroundColor")
    }

    var selectedModuleName: String {
        guard !selectedModuleId.isEmpty,
              let record = moduleStore.records.first(where: { $0.id == selectedModuleId }) else {
            return "All Modules"
        }
        return record.name
    }

    func performSearch() {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let index = searchHistory.firstIndex(of: trimmed) {
            searchHistory.remove(at: index)
        }
        searchHistory.insert(trimmed, at: 0)
        saveHistory()

        activeQuery = trimmed
        isShowingResults = true
    }

    func loadHistory() {
        guard !storedHistoryData.isEmpty,
              let history = try? JSONDecoder().decode([String].self, from: storedHistoryData) else {
            searchHistory = []
            return
        }
        searchHistory = history
    }

    func saveHistory() {
        storedHistoryData = (try? JSONEncoder().encode(searchHistory)) ?? Data()
    }

    func deleteHistoryItem(_ query: String) {
        guard let index = searchHistory.firstIndex(of: query) else { return }
        searchHistory.remove(at: index)
        saveHistory()
    }

    func selectModule(id: String) {
        selectedModuleId = id
    }
}
