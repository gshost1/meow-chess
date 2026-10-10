import ChessCore
import Foundation

/// Swift wrapper around the Rust engine's C interface.
enum Engine {
    enum EngineError: LocalizedError {
        case failed(String)
        var errorDescription: String? {
            if case .failed(let m) = self { return m }
            return nil
        }
    }

    private final class ProgressBox {
        let report: (Double) -> Void
        init(_ report: @escaping (Double) -> Void) { self.report = report }
    }

    /// Runs the full game review off the main thread. Returns the decoded analysis and its raw JSON.
    static func analyze(
        pgn: String,
        username: String?,
        msPerMove: UInt32,
        progress: @escaping (Double) -> Void
    ) async throws -> (GameAnalysis, Data) {
        try await Task.detached(priority: .userInitiated) {
            let box = ProgressBox(progress)
            let ctx = Unmanaged.passRetained(box).toOpaque()
            defer { Unmanaged<ProgressBox>.fromOpaque(ctx).release() }

            let callback: cc_progress_cb = { done, total, ctx in
                guard let ctx else { return }
                let box = Unmanaged<ProgressBox>.fromOpaque(ctx).takeUnretainedValue()
                box.report(Double(done) / Double(max(total, 1)))
            }

            let raw: UnsafeMutablePointer<CChar>? = pgn.withCString { pgnPtr in
                if let username {
                    return username.withCString { userPtr in
                        cc_analyze_pgn(pgnPtr, userPtr, msPerMove, callback, ctx)
                    }
                }
                return cc_analyze_pgn(pgnPtr, nil, msPerMove, callback, ctx)
            }
            guard let raw else { throw EngineError.failed("Engine returned nothing") }
            let json = String(cString: raw)
            cc_free_string(raw)

            let data = Data(json.utf8)
            let envelope = try decoder.decode(EngineEnvelope.self, from: data)
            guard envelope.ok, let analysis = envelope.analysis else {
                throw EngineError.failed(envelope.error ?? "Analysis failed")
            }
            return (analysis, try encoder.encode(analysis))
        }.value
    }

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()
}
