//
//  SearchResultsView.swift
//  Celestia
//
//  Created by Francesco on 31/05/26.
//

import SwiftUI

struct SearchResultsView: View {
    @EnvironmentObject private var moduleStore: ModuleStore
    @Binding var selectedModuleId: String
    let query: String
    
    @State private var results: [ModuleSearchItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isShowingModulePicker = false
    @State private var activeLoadId = UUID()
    
    var body: some View {
        ZStack {
            if selectedModuleId.isEmpty {
                allModulesGrid
            } else {
                singleModuleList
            }
            
            if isLoading {
                ProgressView()
                    .scaleEffect(1.2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(query)
        .background(backgroundColor)
        .toolbar {
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
        .confirmationDialog("Change Source", isPresented: $isShowingModulePicker, titleVisibility: .visible) {
            Button("All Modules") { selectModule(id: "") }
            
            ForEach(moduleStore.records) { record in
                Button(record.name) { selectModule(id: record.id) }
            }
        }
        .task { await loadResults() }
    }
}

private extension SearchResultsView {
    var backgroundColor: Color {
        Color("SecondaryBackgroundColor")
    }
    
    var allModulesGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                statusSection
                
                if shouldShowResultsGrid {
                    ForEach(groupedResults, id: \.moduleName) { group in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(group.moduleName)
                                .font(.headline)
                                .padding(.horizontal, 16)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(alignment: .top, spacing: 14) {
                                    ForEach(group.items) { entry in
                                        SlimAnimeCard(title: entry.title, imageURL: entry.imageURL)
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 12)
        }
        .opacity(isLoading ? 0 : 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(backgroundColor)
    }
    
    var singleModuleList: some View {
        List {
            if let errorMessage {
                Section(selectedModuleName) {
                    Text(errorMessage)
                        .foregroundStyle(.secondary)
                }
                .listRowBackground(Color("SecondaryBackgroundColor"))
            } else if results.isEmpty {
                Section(selectedModuleName) {
                    VStack(spacing: 12) {
                        emptyResultsView
                        Button("Change Source") {
                            isShowingModulePicker = true
                        }
                        .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
                }
                .listRowBackground(Color("SecondaryBackgroundColor"))
            } else {
                Section {
                    ForEach(results) { entry in
                        HStack(spacing: 12) {
                            RemoteImageView(url: entry.imageURL, cornerRadius: 0)
                                .frame(width: 86, height: 130)
                            
                            Text(entry.title)
                                .font(.system(size: 15, weight: .regular))
                                .foregroundStyle(.primary)
                                .lineLimit(3)
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                        .listRowBackground(Color("SecondaryBackgroundColor"))
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .opacity(isLoading ? 0 : 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(backgroundColor)
    }
    
    var statusSection: some View {
        Group {
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
            } else if results.isEmpty {
                emptyResultsView
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
            }
        }
    }
    
    var emptyResultsView: some View {
        VStack(spacing: 12) {
            Text("No results found")
                .font(.headline)
            Text("Try another module or search term.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    var shouldShowResultsGrid: Bool {
        !results.isEmpty && errorMessage == nil && !isLoading
    }
    
    var groupedResults: [(moduleName: String, items: [ModuleSearchItem])] {
        let grouped = Dictionary(grouping: results) { $0.moduleName }
        let orderedNames = moduleStore.records.map { $0.name }
        
        let sortedNames = grouped.keys.sorted { lhs, rhs in
            let leftIndex = orderedNames.firstIndex(of: lhs) ?? orderedNames.count
            let rightIndex = orderedNames.firstIndex(of: rhs) ?? orderedNames.count
            return leftIndex == rightIndex ? lhs < rhs : leftIndex < rightIndex
        }
        
        return sortedNames.map { name in
            (moduleName: name, items: grouped[name] ?? [])
        }
    }
    
    var selectedModuleName: String {
        guard !selectedModuleId.isEmpty,
              let record = moduleStore.records.first(where: { $0.id == selectedModuleId }) else {
            return "All Modules"
        }
        return record.name
    }
    
    func loadResults() async {
        let loadId = UUID()
        activeLoadId = loadId
        isLoading = true
        errorMessage = nil
        
        do {
            let allResults = try await moduleStore.search(keyword: query)
            guard activeLoadId == loadId else { return }
            
            if selectedModuleId.isEmpty {
                results = allResults
            } else if let record = moduleStore.records.first(where: { $0.id == selectedModuleId }) {
                results = allResults.filter { $0.moduleName == record.name }
            } else {
                results = allResults
            }
        } catch {
            guard activeLoadId == loadId else { return }
            errorMessage = error.localizedDescription
        }
        
        guard activeLoadId == loadId else { return }
        isLoading = false
    }
    
    func selectModule(id: String) {
        selectedModuleId = id
        Task { await loadResults() }
    }
}
