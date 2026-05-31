//
//  ModuleModels.swift
//  Celestia
//
//  Created by Francesco on 31/05/26.
//

import Foundation

struct ModuleDefinition: Identifiable, Hashable {
    let id: String
    let name: String
    let script: String
}

struct ModuleSourcePayload: Decodable, Hashable {
    let sourceName: String
    let scriptUrl: String
    let version: String?
    let language: String?
    let baseUrl: String?
    let searchBaseUrl: String?
    let type: String?
    let asyncJS: Bool?
}

struct ModuleRecord: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let jsonURL: String
    let scriptFileName: String
    let jsonFileName: String
    let addedAt: Date
}

struct ModuleSearchItem: Identifiable, Hashable {
    let id: UUID
    let moduleName: String
    let title: String
    let imageURL: URL?
    let href: String
}
