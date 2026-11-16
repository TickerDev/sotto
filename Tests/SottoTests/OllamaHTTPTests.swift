import XCTest
import Network
@testable import SottoProviders
import SottoTools

/// Real loopback HTTP fixtures. They never run model inference or native actions.
private final class LocalHTTPFixture: @unchecked Sendable {
    struct Reply: Sendable { var status = 200; var headers = ""; var body: String }
    private let listener: NWListener
    private let queue = DispatchQueue(label: "sotto.tests.local-http")
    private let lock = NSLock()
    private var received: [String] = []
    private var connections: [NWConnection] = [] // accessed only on queue
    let reply: @Sendable (String) -> Reply
    init(reply: @escaping @Sendable (String) -> Reply) throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
        self.reply = reply
    }
    var requests: [String] { lock.withLock { received } }
    func start() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    self.listener.stateUpdateHandler = nil
                    continuation.resume(returning: "http://127.0.0.1:\(self.listener.port!.rawValue)")
                case .failed(let error):
                    self.listener.stateUpdateHandler = nil; continuation.resume(throwing: error)
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                guard let self else { connection.cancel(); return }
                self.connections.append(connection); connection.start(queue: self.queue)
                self.read(connection, accumulated: Data())
            }
            listener.start(queue: queue)
        }
    }
    private func read(_ connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, complete, error in
            guard let self, error == nil else { connection.cancel(); return }
            var data = accumulated; if let content { data.append(content) }
            guard data.count <= 131072 else { connection.cancel(); return }
            if let boundary = data.range(of: Data("\r\n\r\n".utf8)) {
                let headers = String(decoding: data[..<boundary.lowerBound], as: UTF8.self)
                let length = headers.components(separatedBy: "\r\n").first { $0.lowercased().hasPrefix("content-length:") }.flatMap { Int($0.split(separator: ":", maxSplits: 1)[1].trimmingCharacters(in: .whitespaces)) } ?? 0
                if data.count >= boundary.upperBound + length {
                    let request = String(decoding: data, as: UTF8.self)
                    self.lock.withLock { self.received.append(request) }
                    let reply = self.reply(request)
                    let response = "HTTP/1.1 \(reply.status) Fixture\r\nContent-Type: application/json\r\nConnection: close\r\nContent-Length: \(reply.body.utf8.count)\r\n\(reply.headers)\r\n\(reply.body)"
                    connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
                    return
                }
            }
            if complete { connection.cancel() } else { self.read(connection, accumulated: data) }
        }
    }
    func stop() {
        listener.cancel()
        queue.async { [self] in connections.forEach { $0.cancel() }; connections = [] }
    }
}

final class OllamaHTTPTests: XCTestCase, @unchecked Sendable {
    func testRealTransportBlocksRedirects() async throws {
        let fixture = try LocalHTTPFixture { _ in .init(status: 302, headers: "Location: /redirected\r\n", body: "") }
        let address = try await fixture.start(); defer { fixture.stop() }
        do { _ = try await OllamaProvider(endpoint: address, model: "fixture").models(); XCTFail("Redirect must not be followed") }
        catch { XCTAssertTrue(error.localizedDescription.contains("HTTP 302")) }
        XCTAssertEqual(fixture.requests.count, 1)
        XCTAssertFalse(fixture.requests[0].contains("Authorization:"))
    }
    func testCloudMetadataStopsBeforeAnyTranscriptIsSent() async throws {
        let fixture = try LocalHTTPFixture { _ in .init(body: #"{"capabilities":["tools"],"remote_host":"https://cloud.invalid"}"#) }
        let address = try await fixture.start(); defer { fixture.stop() }
        let provider = try OllamaProvider(endpoint: address, model: "cloud-alias")
        do {
            for try await _ in provider.stream(input: [.object(["role": .string("user"), "content": .string("PRIVATE_TRANSCRIPT_MARKER")])], tools: [], instructions: "trusted") {}
            XCTFail("Cloud-backed alias must be rejected")
        } catch { XCTAssertTrue(error.localizedDescription.contains("Cloud-backed")) }
        XCTAssertEqual(fixture.requests.count, 1)
        XCTAssertTrue(fixture.requests[0].hasPrefix("POST /api/show "))
        XCTAssertFalse(fixture.requests[0].contains("PRIVATE_TRANSCRIPT_MARKER"))
    }
    func testTransportDecodesActualNDJSONAndRejectsMissingCompletion() async throws {
        for completed in [true, false] {
            let fixture = try LocalHTTPFixture { request in
                if request.hasPrefix("POST /api/show ") { return .init(body: #"{"capabilities":["completion","tools"]}"#) }
                return .init(body: #"{"message":{"role":"assistant","content":"fixture answer"},"done":false}"# + "\n" + (completed ? #"{"done":true,"done_reason":"stop"}"# + "\n" : ""))
            }
            let address = try await fixture.start(); defer { fixture.stop() }
            var answer = "", outputs = 0
            do {
                for try await event in try OllamaProvider(endpoint: address, model: "fixture").stream(input: [.object(["role": .string("user"), "content": .string("hello")])], tools: [], instructions: "trusted") {
                    switch event { case .text(let text): answer += text; case .output: outputs += 1 }
                }
                XCTAssertTrue(completed)
            } catch { XCTAssertFalse(completed); XCTAssertTrue(error.localizedDescription.contains("disconnected")) }
            XCTAssertEqual(answer, "fixture answer"); XCTAssertEqual(outputs, completed ? 1 : 0)
            XCTAssertFalse(fixture.requests.joined().lowercased().contains("authorization:"))
        }
    }
}
