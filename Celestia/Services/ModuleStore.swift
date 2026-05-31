//
//  ModuleStore.swift
//  Celestia
//
//  Created by Francesco on 31/05/26.
//

import CryptoKit
import Foundation

@MainActor
final class ModuleStore: ObservableObject {
    static let shared = ModuleStore()
    @Published private(set) var records: [ModuleRecord] = []
    
    private let fileManager = FileManager.default
    private let modulesDirectory: URL
    private let indexURL: URL
    private var runtimeCache: [String: ModuleRuntime] = [:]
    
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
    
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    
    private init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        let base = documents?.appendingPathComponent("modules", isDirectory: true)
        self.modulesDirectory = base ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.indexURL = modulesDirectory.appendingPathComponent("modules.json")
        
        ensureDirectoriesExist()
        loadIndex()
    }
    
    func addModule(from urlString: String) async throws {
        let jsonURL = try validatedURL(from: urlString)
        let payload = try await fetchPayload(from: jsonURL)
        let (scriptString, scriptData, jsonData) = try await fetchScript(for: payload, jsonURL: urlString)
        
        let moduleID = makeModuleID(name: payload.sourceName, scriptURL: payload.scriptUrl)
        try persistFiles(jsonData: jsonData, scriptData: scriptData, moduleID: moduleID)
        
        let record = ModuleRecord(
            id: moduleID,
            name: payload.sourceName,
            jsonURL: urlString.trimmingCharacters(in: .whitespacesAndNewlines),
            scriptFileName: scriptFileName(for: moduleID),
            jsonFileName: jsonFileName(for: moduleID),
            addedAt: Date()
        )
        
        upsertRecord(record)
        runtimeCache[moduleID] = try makeRuntime(id: moduleID, name: payload.sourceName, script: scriptString)
    }
    
    func removeModule(id: String) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        let record = records[index]
        deleteFiles(for: record)
        runtimeCache.removeValue(forKey: id)
        records.remove(at: index)
        saveIndex()
    }
    
    func search(keyword: String) async throws -> [ModuleSearchItem] {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        
        return try await withThrowingTaskGroup(of: [ModuleSearchItem].self) { group in
            for record in records {
                group.addTask { [weak self] in
                    guard let self else { return [] }
                    let runtime = try await self.loadOrCacheRuntime(for: record)
                    let result = try await runtime.searchResults(keyword: trimmed)
                    return await self.parseSearchResults(result, moduleName: record.name)
                }
            }
            var all: [ModuleSearchItem] = []
            for try await items in group { all.append(contentsOf: items) }
            return all
        }
    }

    func fetchMediaDetail(for item: ModuleSearchItem) async throws -> ModuleMediaDetail {
        guard let record = records.first(where: { $0.name == item.moduleName }) else {
            throw ModuleStoreError.moduleNotFound(item.moduleName)
        }

        let runtime = try loadOrCacheRuntime(for: record)
        let details = try await runtime.extractDetails(url: item.href)
        let episodes = try? await runtime.extractEpisodes(url: item.href)

        return ModuleMediaDetail.parse(details: details, episodes: episodes, fallbackItem: item)
    }
}

// MARK: - Persistence

private extension ModuleStore {
    func ensureDirectoriesExist() {
        guard !fileManager.fileExists(atPath: modulesDirectory.path) else { return }
        try? fileManager.createDirectory(at: modulesDirectory, withIntermediateDirectories: true)
    }
    
    func loadIndex() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? decoder.decode([ModuleRecord].self, from: data) else { return }
        records = decoded
    }
    
    func saveIndex() {
        guard let data = try? encoder.encode(records) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }
    
    func upsertRecord(_ record: ModuleRecord) {
        if let index = records.firstIndex(where: { $0.id == record.id }) {
            records[index] = record
        } else {
            records.append(record)
        }
        saveIndex()
    }
    
    func deleteFiles(for record: ModuleRecord) {
        let toDelete = [record.scriptFileName, record.jsonFileName]
            .map { modulesDirectory.appendingPathComponent($0) }
        toDelete.forEach { try? fileManager.removeItem(at: $0) }
    }
    
    func persistFiles(jsonData: Data, scriptData: Data, moduleID: String) throws {
        try jsonData.write(to: modulesDirectory.appendingPathComponent(jsonFileName(for: moduleID)), options: .atomic)
        try scriptData.write(to: modulesDirectory.appendingPathComponent(scriptFileName(for: moduleID)), options: .atomic)
    }
}

// MARK: - Networking

private extension ModuleStore {
    func fetchPayload(from url: URL) async throws -> ModuleSourcePayload {
        let (data, _) = try await URLSession.custom.data(from: url)
        return try decoder.decode(ModuleSourcePayload.self, from: data)
    }
    
    func fetchScript(for payload: ModuleSourcePayload, jsonURL: String) async throws -> (String, Data, Data) {
        let (jsonData, _) = try await URLSession.custom.data(from: try validatedURL(from: jsonURL))
        let scriptURL = try validatedURL(from: payload.scriptUrl)
        let (scriptData, _) = try await URLSession.custom.data(from: scriptURL)
        
        guard let scriptString = String(data: scriptData, encoding: .utf8),
              !scriptString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ModuleStoreError.invalidScriptEncoding
        }
        
        return (scriptString, scriptData, jsonData)
    }
}

// MARK: - Runtime

private extension ModuleStore {
    func loadOrCacheRuntime(for record: ModuleRecord) throws -> ModuleRuntime {
        if let cached = runtimeCache[record.id] { return cached }
        
        let url = modulesDirectory.appendingPathComponent(record.scriptFileName)
        guard let data = try? Data(contentsOf: url),
              let script = String(data: data, encoding: .utf8),
              !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ModuleStoreError.missingScriptFile(record.name)
        }
        
        let runtime = try makeRuntime(id: record.id, name: record.name, script: script)
        runtimeCache[record.id] = runtime
        return runtime
    }
    
    func makeRuntime(id: String, name: String, script: String) throws -> ModuleRuntime {
        try ModuleRuntime(module: ModuleDefinition(id: id, name: name, script: script))
    }
}

// MARK: - Parsing

private extension ModuleStore {
    func parseSearchResults(_ result: Any, moduleName: String) -> [ModuleSearchItem] {
        let array: [Any]
        
        if let direct = result as? [Any] {
            array = direct
        } else if let string = result as? String,
                  let data = string.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [Any] {
            array = json
        } else {
            return []
        }
        
        return array.compactMap { parseSearchItem($0, moduleName: moduleName) }
    }
    
    func parseSearchItem(_ payload: Any, moduleName: String) -> ModuleSearchItem? {
        guard let dict = payload as? [String: Any],
              let title = stringValue(dict["title"]),
              let href = stringValue(dict["href"]) else { return nil }
        
        let imageURL = stringValue(dict["image"]).flatMap(URL.init(string:))
        
        return ModuleSearchItem(
            id: UUID(),
            moduleName: moduleName,
            title: title,
            imageURL: imageURL,
            href: href
        )
    }
    
    func stringValue(_ value: Any?) -> String? {
        switch value {
        case let s as String: return s
        case let n as NSNumber: return n.stringValue
        default: return nil
        }
    }
}

// MARK: - Utilities

private extension ModuleStore {
    func validatedURL(from rawValue: String) throws -> URL {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else {
            throw ModuleStoreError.invalidURL(trimmed)
        }
        return url
    }
    
    func makeModuleID(name: String, scriptURL: String) -> String {
        let input = "\(name.lowercased())|\(scriptURL.lowercased())"
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    func scriptFileName(for id: String) -> String { "\(id).js" }
    func jsonFileName(for id: String) -> String { "\(id).json" }
}

// MARK: - Errors

private extension ModuleStore {
    enum ModuleStoreError: LocalizedError {
        case invalidURL(String)
        case missingScriptFile(String)
        case invalidScriptEncoding
        case moduleNotFound(String)
        
        var errorDescription: String? {
            switch self {
            case .invalidURL(let url):         return "Invalid URL: \(url)"
            case .missingScriptFile(let name): return "Missing script file for module: \(name)"
            case .invalidScriptEncoding:       return "Script file is not valid UTF-8."
            case .moduleNotFound(let name):    return "Unable to find a module named \(name)."
            }
        }
    }
}
