import Foundation

struct CommandDescriptor: Decodable, Identifiable, Equatable {
    struct Input: Decodable, Equatable { let hint: String? }
    let name: String
    let description: String
    let input: Input?
    var id: String { name }

    static func decode(_ value: Any) throws -> [CommandDescriptor] {
        let data = try JSONSerialization.data(withJSONObject: value)
        let commands = try JSONDecoder().decode([CommandDescriptor].self, from: data)
        var names = Set<String>()
        return commands.filter {
            $0.name.range(of: #"^[a-z][a-z0-9_-]*$"#, options: .regularExpression) != nil
                && names.insert($0.name).inserted
        }.sorted { $0.name < $1.name }
    }
}
