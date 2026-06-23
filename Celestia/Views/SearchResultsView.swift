//
//  SearchResultsView.swift
//  Celestia
//
//  Created by Francesco on 31/05/26.
//

import SwiftUI

private enum ModuleLoadState {
    case loading
    case loaded([ModuleSearchItem])
    case failed(String)
}

struct SearchResultsView: View {
    @EnvironmentObject private var moduleStore: ModuleStore
    @Binding var selectedModuleId: String
    let query: String
    
    @State private var moduleStates: [String: ModuleLoadState] = [:]
    
    @State private var singleResults: [ModuleSearchItem] = []
    @State private var singleIsLoading = false
    @State private var singleErrorMessage: String?
    
    @State private var isShowingModulePicker = false
    @State private var activeLoadId = UUID()
    @State private var selectedResult: ModuleSearchItem?
    @State private var hasLoaded = false
    
    private let stripHeight: CGFloat = 200
    
    var body: some View {
        ZStack {
            if selectedModuleId.isEmpty {
                allModulesGrid
            } else {
                singleModuleList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(query)
        .background(backgroundColor)
        .navigationDestination(isPresented: Binding(
            get: { selectedResult != nil },
            set: { if !$0 { selectedResult = nil } }
        )) {
            if let item = selectedResult {
                MediaDetailView(item: item)
                    .environmentObject(moduleStore)
            }
        }
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
        .onAppear {
            guard !hasLoaded else { return }
            hasLoaded = true
            triggerLoad()
        }
        .onChange(of: selectedModuleId) { _ in
            triggerLoad()
        }
    }
}

// MARK: - Views

private extension SearchResultsView {
    var backgroundColor: Color {
        Color("SecondaryBackgroundColor")
    }
    
    var allModulesGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(moduleStore.records) { record in
                    moduleRow(for: record)
                }
            }
            .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(backgroundColor)
    }
    
    @ViewBuilder
    func moduleRow(for record: ModuleRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(record.name)
                .font(.headline)
                .padding(.horizontal, 16)
            
            moduleRowContent(for: record)
                .frame(height: stripHeight)
        }
    }
    
    @ViewBuilder
    func moduleRowContent(for record: ModuleRecord) -> some View {
        switch moduleStates[record.id] {
        case .none, .loading:
            ProgressView()
                .frame(maxWidth: .infinity)
            
        case .loaded(let items) where items.isEmpty:
            Text("No results")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
            
        case .loaded(let items):
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(items) { entry in
                        Button {
                            selectedResult = entry
                        } label: {
                            SlimAnimeCard(title: entry.title, imageURL: entry.imageURL)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
            
        case .failed(let message):
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity)
        }
    }
    
    var singleModuleList: some View {
        List {
            if let errorMessage = singleErrorMessage {
                Section(selectedModuleName) {
                    Text(errorMessage)
                        .foregroundStyle(.secondary)
                }
                .listRowBackground(Color("SecondaryBackgroundColor"))
            } else if singleIsLoading {
                Section(selectedModuleName) {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: stripHeight)
                }
                .listRowBackground(Color("SecondaryBackgroundColor"))
            } else if singleResults.isEmpty {
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
                    ForEach(singleResults) { entry in
                        Button {
                            selectedResult = entry
                        } label: {
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
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color("SecondaryBackgroundColor"))
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(backgroundColor)
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
    
    var selectedModuleName: String {
        guard !selectedModuleId.isEmpty,
              let record = moduleStore.records.first(where: { $0.id == selectedModuleId }) else {
            return "All Modules"
        }
        return record.name
    }
}

// MARK: - Loading logic

private extension SearchResultsView {
    func triggerLoad() {
        let loadId = UUID()
        activeLoadId = loadId
        
        if selectedModuleId.isEmpty {
            loadAllModules(loadId: loadId)
        } else {
            Task { await loadSingleModule(loadId: loadId) }
        }
    }
    
    func loadAllModules(loadId: UUID) {
        moduleStates = Dictionary(
            uniqueKeysWithValues: moduleStore.records.map { ($0.id, .loading) }
        )
        
        for record in moduleStore.records {
            Task {
                await loadModule(record: record, loadId: loadId)
            }
        }
    }
    
    func loadModule(record: ModuleRecord, loadId: UUID) async {
        do {
            let items = try await moduleStore.search(keyword: query, moduleId: record.id)
            guard activeLoadId == loadId else { return }
            moduleStates[record.id] = .loaded(items)
        } catch {
            guard activeLoadId == loadId else { return }
            moduleStates[record.id] = .failed(error.localizedDescription)
        }
    }
    
    // MARK: Single-module load
    func loadSingleModule(loadId: UUID) async {
        singleIsLoading = true
        singleErrorMessage = nil
        singleResults = []
        
        do {
            guard let record = moduleStore.records.first(where: { $0.id == selectedModuleId }) else {
                singleIsLoading = false
                return
            }
            let items = try await moduleStore.search(keyword: query, moduleId: record.id)
            guard activeLoadId == loadId else { return }
            singleResults = items
        } catch {
            guard activeLoadId == loadId else { return }
            singleErrorMessage = error.localizedDescription
        }
        
        guard activeLoadId == loadId else { return }
        singleIsLoading = false
    }
    
    func selectModule(id: String) {
        selectedModuleId = id
        triggerLoad()
    }
}
