import Foundation

// MARK: - 目录模型

struct ModelCatalog: Codable {
    let `default`: ModelCatalogSelection
    let groups: [ModelProviderGroup]
    let failures: [ModelCatalogFailure]?

    enum CodingKeys: String, CodingKey {
        case groups, failures
        case `default` = "default"
    }
}

struct ModelCatalogSelection: Codable, Hashable {
    let provider: String
    let model: String
    let reasoningEffort: String?
}

struct ModelProviderGroup: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let models: [ModelCatalogModel]
}

struct ModelCatalogModel: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let description: String?
    let reasoning: ModelReasoning?
}

struct ModelReasoning: Codable, Hashable {
    let efforts: [ModelReasoningEffort]
    let defaultEffort: String?
}

struct ModelReasoningEffort: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let description: String?
}

struct ModelCatalogFailure: Codable, Hashable {
    let id: String
    let name: String?
    let message: String?
}
