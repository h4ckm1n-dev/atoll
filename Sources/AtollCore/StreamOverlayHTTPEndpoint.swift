import Foundation
import Network
import os

/// Loopback-only HTTP endpoint for OBS/browser-source overlays.
///
/// The endpoint is intentionally read-only and unauthenticated because OBS
/// browser sources cannot sign HMAC requests. It binds to 127.0.0.1 only and
/// serves already-redacted overlay data.
public final class StreamOverlayHTTPEndpoint: @unchecked Sendable {
    public static let defaultPort: UInt16 = 47619

    private static let logger = Logger(subsystem: "app.atoll", category: "StreamOverlayHTTPEndpoint")
    private let queue = DispatchQueue(label: "app.atoll.stream-overlay.http", qos: .userInitiated)
    private let port: UInt16
    private var listener: NWListener?

    public var snapshotProvider: @Sendable () -> StreamOverlaySnapshot = { .empty }

    public init(port: UInt16 = 47_619) {
        self.port = port
    }

    public var overlayURLString: String {
        "http://127.0.0.1:\(port)/overlay"
    }

    public var statusURLString: String {
        "http://127.0.0.1:\(port)/status"
    }

    public func start() {
        queue.async { [weak self] in
            self?.startListener()
        }
    }

    public func stop() {
        queue.async { [weak self] in
            self?.listener?.cancel()
            self?.listener = nil
        }
    }

    private func startListener() {
        guard listener == nil else { return }

        do {
            let params = NWParameters.tcp
            params.requiredLocalEndpoint = NWEndpoint.hostPort(
                host: .ipv4(.loopback),
                port: NWEndpoint.Port(rawValue: port) ?? .any
            )

            let listener = try NWListener(using: params)
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    Self.logger.info("Stream overlay listening at \(self?.overlayURLString ?? "", privacy: .public)")
                case let .failed(error):
                    Self.logger.error("Stream overlay listener failed: \(error.localizedDescription, privacy: .private)")
                    self?.queue.async { [weak self] in
                        self?.listener = nil
                    }
                case .cancelled:
                    Self.logger.info("Stream overlay listener cancelled")
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            Self.logger.error("Failed to create stream overlay listener: \(error.localizedDescription, privacy: .private)")
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, error in
            guard let self else {
                connection.cancel()
                return
            }
            if let error {
                Self.logger.debug("Stream overlay receive error: \(error.localizedDescription, privacy: .private)")
                connection.cancel()
                return
            }
            guard let data, let request = String(data: data, encoding: .utf8) else {
                self.send(connection, status: "400 Bad Request", contentType: "text/plain; charset=utf-8", body: "bad request")
                return
            }
            let route = Self.route(for: request)
            let response = self.response(for: route)
            self.send(connection, status: response.status, contentType: response.contentType, body: response.body)
        }
    }

    private struct Response {
        var status: String
        var contentType: String
        var body: String
    }

    private enum Route: Equatable {
        case overlay
        case status
        case health
        case notFound
        case methodNotAllowed
    }

    private static func route(for request: String) -> Route {
        guard let requestLine = request.components(separatedBy: .newlines).first else {
            return .notFound
        }
        let parts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard parts.count >= 2 else { return .notFound }
        guard parts[0] == "GET" else { return .methodNotAllowed }

        switch parts[1] {
        case "/", "/overlay":
            return .overlay
        case "/status":
            return .status
        case "/health":
            return .health
        default:
            return .notFound
        }
    }

    private func response(for route: Route) -> Response {
        switch route {
        case .overlay:
            return Response(status: "200 OK", contentType: "text/html; charset=utf-8", body: Self.overlayHTML)
        case .status:
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = (try? encoder.encode(snapshotProvider())) ?? Data("{}".utf8)
            let body = String(data: data, encoding: .utf8) ?? "{}"
            return Response(status: "200 OK", contentType: "application/json; charset=utf-8", body: body)
        case .health:
            return Response(status: "200 OK", contentType: "application/json; charset=utf-8", body: #"{"ok":true}"#)
        case .methodNotAllowed:
            return Response(status: "405 Method Not Allowed", contentType: "application/json; charset=utf-8", body: #"{"error":"method not allowed"}"#)
        case .notFound:
            return Response(status: "404 Not Found", contentType: "application/json; charset=utf-8", body: #"{"error":"not found"}"#)
        }
    }

    private func send(_ connection: NWConnection, status: String, contentType: String, body: String) {
        let headers = """
        HTTP/1.1 \(status)\r
        Content-Type: \(contentType)\r
        Cache-Control: no-store\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r

        """
        let response = headers + body
        connection.send(content: Data(response.utf8), isComplete: true, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

extension StreamOverlayHTTPEndpoint {
    static let overlayHTML = """
    <!doctype html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>Atoll Stream Overlay</title>
      <style>
        :root { color-scheme: dark; font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", sans-serif; }
        body { margin: 0; background: transparent; overflow: hidden; }
        .wrap { width: 760px; padding: 18px; box-sizing: border-box; }
        .panel { color: #cdd6f4; background: rgba(17, 17, 27, .78); border: 1px solid rgba(205, 214, 244, .18); border-radius: 18px; padding: 16px; box-shadow: 0 18px 60px rgba(0,0,0,.32); backdrop-filter: blur(18px); }
        .top { display: flex; align-items: center; justify-content: space-between; gap: 14px; margin-bottom: 12px; }
        .brand { font-size: 14px; font-weight: 800; letter-spacing: .04em; text-transform: uppercase; color: #89b4fa; }
        .counts { font-size: 13px; color: rgba(205,214,244,.7); }
        .sessions { display: grid; gap: 10px; }
        .session { display: grid; grid-template-columns: 10px 1fr auto; gap: 10px; align-items: start; padding: 10px 0; border-top: 1px solid rgba(205,214,244,.08); }
        .session:first-child { border-top: 0; }
        .dot { width: 10px; height: 10px; border-radius: 999px; margin-top: 5px; background: #a6e3a1; }
        .attention .dot { background: #fab387; box-shadow: 0 0 18px rgba(250,179,135,.7); }
        .running .dot { background: #89b4fa; }
        .completed .dot { background: #a6e3a1; }
        .headline { font-size: 16px; line-height: 1.2; font-weight: 750; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
        .detail { margin-top: 4px; font-size: 13px; line-height: 1.28; color: rgba(205,214,244,.68); display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden; }
        .badge { font-size: 11px; font-weight: 800; color: rgba(205,214,244,.78); background: rgba(49,50,68,.85); border-radius: 999px; padding: 4px 8px; white-space: nowrap; }
        .empty { font-size: 14px; color: rgba(205,214,244,.62); padding: 10px 0 2px; }
      </style>
    </head>
    <body>
      <main class="wrap">
        <section class="panel">
          <div class="top">
            <div class="brand">Atoll Live</div>
            <div class="counts" id="counts">Waiting for agents</div>
          </div>
          <div class="sessions" id="sessions"><div class="empty">No visible sessions</div></div>
        </section>
      </main>
      <script>
        const counts = document.getElementById('counts');
        const sessions = document.getElementById('sessions');
        function escapeHTML(value) {
          return String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
        }
        function render(data) {
          counts.textContent = `${data.liveSessionCount ?? 0} live · ${data.attentionCount ?? 0} attention`;
          const rows = data.sessions ?? [];
          if (!rows.length) {
            sessions.innerHTML = '<div class="empty">No visible sessions</div>';
            return;
          }
          sessions.innerHTML = rows.map(row => `
            <article class="session ${escapeHTML(row.status)}">
              <div class="dot"></div>
              <div>
                <div class="headline">${escapeHTML(row.headline)}</div>
                <div class="detail">${escapeHTML(row.detail || row.statusLabel)}</div>
              </div>
              <div class="badge">${escapeHTML(row.tool)}</div>
            </article>
          `).join('');
        }
        async function refresh() {
          try {
            const res = await fetch('/status', { cache: 'no-store' });
            if (res.ok) render(await res.json());
          } catch (_) {}
        }
        refresh();
        setInterval(refresh, 1000);
      </script>
    </body>
    </html>
    """

    public static func overlayHTMLForTesting() -> String {
        overlayHTML
    }
}
