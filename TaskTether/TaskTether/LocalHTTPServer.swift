//
//  LocalHTTPServer.swift
//  TaskTether
//
//  Created by Hazim Sami on 10/03/2026.
//

import Foundation
import Network

/// The two values Google's OAuth redirect can hand back to us — the
/// authorization code and the `state` we sent on the way out. `state` is
/// optional here only because a malformed/garbage request might carry a
/// code without one; GoogleAuthManager treats a missing state as a
/// rejection, it is not a valid case to act on.
struct AuthCallback {
    let code: String
    let state: String?
}

enum LocalHTTPServerError: Error {
    /// Google redirected back with `error=access_denied` (user cancelled
    /// the consent screen).
    case accessDenied
}

class LocalHTTPServer {

    private var listener: NWListener?
    private var onResult: ((Result<AuthCallback, Error>) -> Void)?

    // Starts listening on an EPHEMERAL port chosen by the system — never a
    // fixed one. A fixed port (previously 8080) collides with anything else
    // on the machine (Homebrew nginx defaults to 8080, dev servers love it),
    // and the OAuth redirect then delivers the auth code to the wrong
    // process. Google desktop OAuth clients accept any loopback port, so
    // the caller builds the redirect URI from the port reported by onReady.
    //
    // The listener is bound to the loopback interface only (127.0.0.1) —
    // never .any — so no other host on the LAN can reach it during sign-in.
    //
    // onReady is called exactly once: with the bound port on success, or
    // nil when the listener could not start.
    func start(onResult: @escaping (Result<AuthCallback, Error>) -> Void, onReady: @escaping (UInt16?) -> Void) {
        self.onResult = onResult

        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: NWEndpoint.Host("127.0.0.1"), port: .any)

        do {
            listener = try NWListener(using: parameters)
        } catch {
            #if DEBUG
            print("Failed to create listener: \(error)")
            #endif
            onReady(nil)
            return
        }

        // Bind failures do NOT throw above — they surface asynchronously
        // here. Without this handler the sign-in button spins forever with
        // no explanation.
        var reported = false
        listener?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                guard !reported else { return }
                reported = true
                let port = self?.listener?.port?.rawValue
                #if DEBUG
                print("Local HTTP server started on port \(port.map(String.init) ?? "?")")
                #endif
                onReady(port)
            case .failed(let error):
                #if DEBUG
                print("Listener failed: \(error)")
                #endif
                self?.stop()
                guard !reported else { return }
                reported = true
                onReady(nil)
            default:
                break
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            connection.start(queue: .global())
            self?.handleConnection(connection)
        }

        listener?.start(queue: .global())
    }

    func stop() {
        listener?.cancel()
        listener = nil
        #if DEBUG
        print("Local HTTP server stopped")
        #endif
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, _, _ in
            guard let self, let data, let request = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }
            self.respond(to: request, on: connection)
        }
    }

    /// Parses the request line, validates it, and sends the matching
    /// response. Every branch ends the connection — either by handing off
    /// to `sendResponse` (which cancels on completion) or by cancelling
    /// directly.
    private func respond(to request: String, on connection: NWConnection) {
        guard let parsed = parseRequestLine(request) else {
            sendResponse(status: "400 Bad Request", html: "", on: connection)
            return
        }

        if parsed.query["error"] != nil {
            sendResponse(status: "200 OK", html: Self.cancelledHTML, on: connection)
            onResult?(.failure(LocalHTTPServerError.accessDenied))
            stop()
            return
        }

        guard let code = parsed.query["code"] else {
            sendResponse(status: "400 Bad Request", html: "", on: connection)
            return
        }

        sendResponse(status: "200 OK", html: Self.successHTML, on: connection)
        onResult?(.success(AuthCallback(code: code, state: parsed.query["state"])))
        stop()
    }

    private struct ParsedRequest {
        let query: [String: String]
    }

    /// Parses `GET /path?query HTTP/1.1` using URLComponents (which handles
    /// percent-decoding for us) rather than substring hunting. Anything
    /// that isn't a well-formed GET request line is rejected.
    private func parseRequestLine(_ request: String) -> ParsedRequest? {
        guard let line = request.components(separatedBy: "\r\n").first else { return nil }

        let parts = line.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count == 3, parts[0] == "GET" else { return nil }
        // Reject anything but origin-form request targets (starting with
        // "/"). Absolute-form targets (e.g. "GET http://evil/?code=..")
        // would otherwise be prefixed onto "http://localhost" below and
        // parsed as a path, letting a crafted request smuggle its own host.
        guard parts[1].hasPrefix("/") else { return nil }
        guard let components = URLComponents(string: "http://localhost" + parts[1]) else { return nil }

        var query: [String: String] = [:]
        for item in components.queryItems ?? [] {
            query[item.name] = item.value
        }
        return ParsedRequest(query: query)
    }

    private func sendResponse(status: String, html: String, on connection: NWConnection) {
        let response = "HTTP/1.1 \(status)\r\nContent-Type: text/html\r\nContent-Length: \(html.utf8.count)\r\n\r\n\(html)"

        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private static let successHTML = """
    <html>
    <head>
        <style>
            body { font-family: -apple-system, sans-serif; display: flex;
                   align-items: center; justify-content: center;
                   height: 100vh; margin: 0; background: #f5f5f7; }
            .card { text-align: center; padding: 40px; background: white;
                    border-radius: 12px; box-shadow: 0 2px 20px rgba(0,0,0,0.1); }
            h1 { color: #1a1a2e; font-size: 24px; margin-bottom: 8px; }
            p { color: #8e8e93; font-size: 16px; }
        </style>
    </head>
    <body>
        <div class="card">
            <h1>TaskTether Connected</h1>
            <p>You can close this tab and return to TaskTether.</p>
        </div>
    </body>
    </html>
    """

    private static let cancelledHTML = """
    <html>
    <head>
        <style>
            body { font-family: -apple-system, sans-serif; display: flex;
                   align-items: center; justify-content: center;
                   height: 100vh; margin: 0; background: #f5f5f7; }
            .card { text-align: center; padding: 40px; background: white;
                    border-radius: 12px; box-shadow: 0 2px 20px rgba(0,0,0,0.1); }
            h1 { color: #1a1a2e; font-size: 24px; margin-bottom: 8px; }
            p { color: #8e8e93; font-size: 16px; }
        </style>
    </head>
    <body>
        <div class="card">
            <h1>Sign-in cancelled</h1>
            <p>You can close this tab and return to TaskTether.</p>
        </div>
    </body>
    </html>
    """
}
