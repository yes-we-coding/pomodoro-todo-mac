import SwiftUI
import WebKit

// MARK: - 本地 HTTP 服务器（纯 Network.framework，无第三方依赖）
// 把内置 WebRoot 通过 http://127.0.0.1:<随机端口> 提供给 WKWebView，
// 这样 localStorage / Service Worker 能像普通网页一样可靠工作。

import Network

final class LocalHTTPServer {
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "pt.localhttp")
    private(set) var port: UInt16 = 0

    private let resourceURL: URL

    init(resourceURL: URL) {
        self.resourceURL = resourceURL
    }

    /// 启动并等待端口就绪，返回实际端口。
    @discardableResult
    func start() -> UInt16 {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        // 只绑定本机回环
        let listener = try! NWListener(using: params, on: .any)
        self.listener = listener

        let sem = DispatchSemaphore(value: 0)

        listener.stateUpdateHandler = { state in
            if case .ready = state { sem.signal() }
            if case .failed = state { sem.signal() }
        }

        listener.newConnectionHandler = { [weak self] conn in
            self?.handle(conn)
        }

        listener.start(queue: queue)
        sem.wait()

        if let p = listener.port {
            port = p.rawValue
        }
        return port
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handle(_ conn: NWConnection) {
        conn.start(queue: queue)
        receiveRequest(conn, buffer: Data())
    }

    private func receiveRequest(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { conn.cancel(); return }
            var buffer = buffer
            if let data = data { buffer.append(data) }

            // 请求头以 \r\n\r\n 结束。本应用只有 GET，不关心 body。
            if let range = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let request = String(decoding: buffer[..<range.lowerBound], as: UTF8.self)
                let response = self.response(for: request)
                self.send(response, on: conn)
                return
            }

            if isComplete || error != nil {
                conn.cancel()
                return
            }
            // 继续读，防止超大/分段请求头（本地基本不会发生）
            if buffer.count > 64 * 1024 { conn.cancel(); return }
            self.receiveRequest(conn, buffer: buffer)
        }
    }

    private func send(_ data: Data, on conn: NWConnection) {
        conn.contentProcessed { _ in
            conn.cancel()
        }
        conn.send(content: data, completion: .contentProcessed { _ in
            conn.cancel()
        })
    }

    // MARK: 路由

    private func response(for request: String) -> Data {
        let firstLine = request.split(separator: "\r\n", maxSplits: 1).first.map(String.init) ?? ""
        let parts = firstLine.split(separator: " ")
        let method = parts.count > 0 ? String(parts[0]) : "GET"
        var rawPath = parts.count > 1 ? String(parts[1]) : "/"

        guard method == "GET" else { return makeError(405, "Method Not Allowed") }

        // 去掉 query
        if let q = rawPath.firstIndex(of: "?") { rawPath = String(rawPath[..<q]) }
        // 去掉 percent encoding
        var path = rawPath.removingPercentEncoding ?? rawPath
        if path.hasPrefix("/") { path.removeFirst() }
        if path.isEmpty { path = "index.html" }

        // 安全：禁止路径穿越，只允许平铺文件
        if path.contains("..") || path.contains("/") {
            return makeError(404, "Not Found")
        }

        let fileURL = resourceURL.appendingPathComponent(path)
        guard let data = try? Data(contentsOf: fileURL) else {
            return makeError(404, "Not Found")
        }

        return makeResponse(status: 200, reason: "OK", contentType: contentType(for: path), body: data)
    }

    private func contentType(for path: String) -> String {
        switch (path as NSString).pathExtension.lowercased() {
        case "html", "htm": return "text/html; charset=utf-8"
        case "js":           return "application/javascript; charset=utf-8"
        case "json", "webmanifest": return "application/manifest+json; charset=utf-8"
        case "css":          return "text/css; charset=utf-8"
        case "png":          return "image/png"
        case "jpg", "jpeg":  return "image/jpeg"
        case "gif":          return "image/gif"
        case "svg":          return "image/svg+xml"
        case "ico":          return "image/x-icon"
        case "webp":         return "image/webp"
        case "woff", "woff2": return "font/woff2"
        default:             return "application/octet-stream"
        }
    }

    private func makeResponse(status: Int, reason: String, contentType: String, body: Data) -> Data {
        var head = ""
        head += "HTTP/1.1 \(status) \(reason)\r\n"
        head += "Content-Type: \(contentType)\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Connection: close\r\n"
        head += "Cache-Control: no-cache\r\n"
        head += "Access-Control-Allow-Origin: *\r\n"
        head += "\r\n"
        var data = Data(head.utf8)
        data.append(body)
        return data
    }

    private func makeError(_ status: Int, _ reason: String) -> Data {
        let body = Data("\(status) \(reason)".utf8)
        return makeResponse(status: status, reason: reason, contentType: "text/plain; charset=utf-8", body: body)
    }
}

// MARK: - 常驻 WebView 持有者（即使弹窗关闭也保持计时与 Web Audio）

final class WebHolder: NSObject, WKUIDelegate, WKNavigationDelegate {
    let webView: WKWebView
    private(set) var baseURL: URL

    init(port: UInt16) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsAirPlayForMediaPlayback = true
        if #available(macOS 11, *) {
            // 允许不经过用户手势即可播放提示音
            config.mediaTypesRequiringUserActionForPlayback = []
        }

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.setValue(false, forKey: "drawsBackground")
        wv.uiDelegate = nil
        self.webView = wv
        self.baseURL = URL(string: "http://127.0.0.1:\(port)/index.html")!
        super.init()
        wv.uiDelegate = self
        wv.navigationDelegate = self
        wv.load(URLRequest(url: baseURL))
    }

    func reload() {
        webView.load(URLRequest(url: baseURL))
    }

    // 允许 window.open / target=_blank 在同一视图打开
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url { webView.load(URLRequest(url: url)) }
        return nil
    }
}

// MARK: - SwiftUI 视图

struct WebContainerView: NSViewRepresentable {
    let holder: WebHolder
    func makeNSView(context: Context) -> WKWebView { holder.webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

struct RootView: View {
    let holder: WebHolder
    var body: some View {
        VStack(spacing: 0) {
            WebContainerView(holder: holder)
            Divider()
            HStack(spacing: 10) {
                Text("🍅 番茄待办").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                Button {
                    holder.reload()
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise").labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderless).font(.system(size: 11))

                Button {
                    NSApp.terminate(nil)
                } label: {
                    Label("退出", systemImage: "power").labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderless).font(.system(size: 11))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.bar)
        }
        .frame(width: 400, height: 680)
    }
}

// MARK: - App

@main
struct PomodoroTodoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            RootView(holder: appDelegate.holder!)
        } label: {
            Text("🍅")
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var holder: WebHolder?
    private var server: LocalHTTPServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 菜单栏 App：不显示 Dock 图标（对应 Info.plist 的 LSUIElement）
        NSApp.setActivationPolicy(.accessory)

        // 资源目录：.app 里为 Contents/Resources/WebRoot；
        // 若找不到则回退到源码仓库的 WebRoot（便于本地 swift run 调试）。
        let resourceURL: URL
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("WebRoot"),
           FileManager.default.fileExists(atPath: bundled.path) {
            resourceURL = bundled
        } else if let top = findSourceWebRoot() {
            resourceURL = top
        } else {
            fatalError("找不到 WebRoot 资源目录")
        }

        let server = LocalHTTPServer(resourceURL: resourceURL)
        let port = server.start()
        self.server = server
        self.holder = WebHolder(port: port)
    }

    /// 向上逐级查找包含 index.html 的 WebRoot 目录（调试用）。
    private func findSourceWebRoot() -> URL? {
        var dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for _ in 0..<6 {
            let candidate = dir.appendingPathComponent("WebRoot")
            let index = candidate.appendingPathComponent("index.html")
            if FileManager.default.fileExists(atPath: index.path) { return candidate }
            dir.deleteLastPathComponent()
        }
        return nil
    }
}
