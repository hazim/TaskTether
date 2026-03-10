//
//  LocalHTTPServer.swift
//  TaskTether
//
//  Created by Hazim Sami on 10/03/2026.
//

import Foundation
import Network

class LocalHTTPServer {
    
    private var listener: NWListener?
    private var onCode: ((String) -> Void)?
    private let port: UInt16 = 8080
    
    func start(onCode: @escaping (String) -> Void) {
        self.onCode = onCode
        
        do {
            listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!)
        } catch {
            print("Failed to create listener: \(error)")
            return
        }
        
        listener?.newConnectionHandler = { [weak self] connection in
            connection.start(queue: .global())
            self?.handleConnection(connection)
        }
        
        listener?.start(queue: .global())
        print("Local HTTP server started on port \(port)")
    }
    
    func stop() {
        listener?.cancel()
        listener = nil
        print("Local HTTP server stopped")
    }
    
    private func handleConnection(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let data = data, let request = String(data: data, encoding: .utf8) else { return }
            
            // Parse the auth code from the GET request line
            // e.g. GET /?code=4/0AX4XfWh...&scope=... HTTP/1.1
            if let code = self?.extractCode(from: request) {
                // Send a success response to the browser
                let html = """
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
                
                let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: \(html.utf8.count)\r\n\r\n\(html)"
                
                connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
                    connection.cancel()
                })
                
                self?.onCode?(code)
                self?.stop()
            }
        }
    }
    
    private func extractCode(from request: String) -> String? {
        // GET /?code=XXXX&... HTTP/1.1
        guard let line = request.components(separatedBy: "\r\n").first,
              let range = line.range(of: "code=") else { return nil }
        
        let after = String(line[range.upperBound...])
        let code = after.components(separatedBy: "&").first?
                        .components(separatedBy: " ").first
        return code
    }
}
