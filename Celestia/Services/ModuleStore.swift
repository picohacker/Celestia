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
    private var controllerCache: [String: JSController] = [:]
    
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
        controllerCache[moduleID] = JSController(moduleName: payload.sourceName, script: scriptString)
    }
    
    func removeModule(id: String) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        let record = records[index]
        deleteFiles(for: record)
        controllerCache.removeValue(forKey: id)
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
                    let controller = try await self.loadOrCacheController(for: record)
                    return try await withCheckedThrowingContinuation { continuation in
                        controller.fetchSearchJS(keyword: trimmed) { items in
                            let mapped = items.map { item in
                                ModuleSearchItem(
                                    id: UUID(),
                                    moduleName: record.name,
                                    title: item.title,
                                    imageURL: item.imageUrl.isEmpty ? nil : URL(string: item.imageUrl),
                                    href: item.href
                                )
                            }
                            continuation.resume(returning: mapped)
                        }
                    }
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

        let controller = try loadOrCacheController(for: record)

        return try await withCheckedThrowingContinuation { continuation in
            controller.fetchDetailsJS(url: item.href) { details, episodes in
                let detail = ModuleMediaDetail.parse(
                    details: details,
                    episodes: episodes,
                    fallbackItem: item
                )
                continuation.resume(returning: detail)
            }
        }
    }

    private func fetchStreamUrlWithCompletion(
        for episode: ModuleMediaEpisode,
        moduleName: String,
        completion: @escaping ((streams: [String]?, subtitles: [String]?, sources: [[String: Any]]?)) -> Void
    ) {
        guard let record = records.first(where: { $0.name == moduleName }) else {
            Logger.shared.log("Module not found: \(moduleName)", type: "Error")
            completion((nil, nil, nil))
            return
        }

        guard let controller = try? loadOrCacheController(for: record) else {
            Logger.shared.log("Failed to load JS controller for: \(moduleName)", type: "Error")
            completion((nil, nil, nil))
            return
        }

        guard let href = episode.href ?? episode.downloadURL, !href.isEmpty else {
            Logger.shared.log("Episode has no href or downloadURL", type: "Error")
            completion((nil, nil, nil))
            return
        }

        controller.fetchStreamUrlJS(episodeUrl: href, completion: completion)
    }
    
    func fetchStreamUrl(for episode: ModuleMediaEpisode, moduleName: String) async -> (streams: [String]?, subtitles: [String]?, sources: [[String: Any]]?) {
        await withCheckedContinuation { continuation in
            fetchStreamUrlWithCompletion(for: episode, moduleName: moduleName) { result in
                continuation.resume(returning: result)
            }
        }
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

// MARK: - JSController cache

private extension ModuleStore {
    func loadOrCacheController(for record: ModuleRecord) throws -> JSController {
        if let cached = controllerCache[record.id] { return cached }
        
        let url = modulesDirectory.appendingPathComponent(record.scriptFileName)
        guard let data = try? Data(contentsOf: url),
              let script = String(data: data, encoding: .utf8),
              !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ModuleStoreError.missingScriptFile(record.name)
        }
        
        let controller = JSController(moduleName: record.name, script: script)
        controllerCache[record.id] = controller
        return controller
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
