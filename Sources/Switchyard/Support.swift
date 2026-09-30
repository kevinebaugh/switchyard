import Foundation

extension Duration {
    var milliseconds: Double {
        Double(components.seconds) * 1000 + Double(components.attoseconds) / 1e15
    }
}

extension URL {
    /// The host for display, or the whole URL when there isn't one.
    var displayHost: String { host ?? absoluteString }
}

/// Small JSON files Switchyard keeps on this Mac (history, rule usage).
enum LocalJSONFile {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static func read<Value: Decodable>(_ type: Value.Type, from url: URL) -> Value? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    static func write<Value: Encodable>(_ value: Value, to url: URL) {
        guard let data = try? encoder.encode(value) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}

/// Coalesces bursts of changes into one write a moment later, off the routing path.
@MainActor
final class DebouncedSave {
    private let delay: Duration
    private var task: Task<Void, Never>?

    init(delay: Duration) {
        self.delay = delay
    }

    func schedule(_ save: @escaping @MainActor () -> Void) {
        task?.cancel()
        task = Task { [delay] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            save()
        }
    }
}
