// codex-usage-widget — always-on-top macOS widget showing your Codex usage limit.
//
// Gets data the supported way: it talks to `codex app-server` (the official
// JSON-RPC interface that ships with Codex CLI) and calls
// `account/rateLimits/read`. It never reads or writes Codex credential files;
// authentication is handled entirely by Codex CLI itself.
//
// Requirements: macOS 13+, Codex CLI installed and logged in (`codex login`).
//
// Build: make build   (or: swiftc -O CodexUsage.swift -o CodexUsage)

import AppKit

// MARK: - Data model

struct Usage {
    let remainingPercent: Double
    let resetsAt: Date?
    let credits: String?
}

enum FetchResult {
    case success(Usage)
    case authError(String)   // not logged in / session invalid
    case toolError(String)   // codex binary missing or RPC failed
}

// MARK: - Codex app-server client

enum CodexClient {
    /// Locate the codex binary: $CODEX_BIN override, then PATH, then common installs.
    static func findCodex() -> String? {
        if let env = ProcessInfo.processInfo.environment["CODEX_BIN"],
           FileManager.default.isExecutableFile(atPath: env) { return env }

        let which = Process()
        which.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        which.arguments = ["sh", "-lc", "command -v codex"]
        let pipe = Pipe()
        which.standardOutput = pipe
        which.standardError = FileHandle.nullDevice
        if (try? which.run()) != nil {
            which.waitUntilExit()
            if let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(),
                                encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !out.isEmpty, FileManager.default.isExecutableFile(atPath: out) {
                return out
            }
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        for candidate in ["\(home)/.local/bin/codex",
                          "/opt/homebrew/bin/codex",
                          "/usr/local/bin/codex"] {
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    /// One-shot JSON-RPC session: initialize, read rate limits, terminate.
    static func fetch(completion: @escaping (FetchResult) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            completion(fetchSync())
        }
    }

    private static func fetchSync() -> FetchResult {
        guard let codexPath = findCodex() else {
            return .toolError("codex CLI not found — install it first")
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: codexPath)
        proc.arguments = ["app-server"]
        let stdin = Pipe(), stdout = Pipe()
        proc.standardInput = stdin
        proc.standardOutput = stdout
        proc.standardError = FileHandle.nullDevice

        do { try proc.run() } catch {
            return .toolError("failed to start codex app-server")
        }
        defer {
            proc.terminate()
            proc.waitUntilExit()
        }

        func send(_ obj: [String: Any]) {
            guard var data = try? JSONSerialization.data(withJSONObject: obj) else { return }
            data.append(0x0A)
            stdin.fileHandleForWriting.write(data)
        }

        // Read newline-delimited JSON until we see a response with the given id.
        var buffer = Data()
        func recv(id: Int, timeout: TimeInterval) -> [String: Any]? {
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                while let nl = buffer.firstIndex(of: 0x0A) {
                    let line = buffer.prefix(upTo: nl)
                    buffer.removeSubrange(...nl)
                    if let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                       obj["id"] as? Int == id {
                        return obj
                    }
                }
                let chunk = stdout.fileHandleForReading.availableData
                if chunk.isEmpty {                       // EOF — process died
                    return nil
                }
                buffer.append(chunk)
            }
            return nil
        }

        send(["jsonrpc": "2.0", "id": 1, "method": "initialize",
              "params": ["clientInfo": ["name": "codex-usage-widget",
                                        "title": "Codex Usage Widget",
                                        "version": "1.0.0"]]])
        guard recv(id: 1, timeout: 15) != nil else {
            return .toolError("codex app-server did not respond")
        }

        send(["jsonrpc": "2.0", "id": 2, "method": "account/rateLimits/read",
              "params": [String: Any]()])
        guard let resp = recv(id: 2, timeout: 30) else {
            return .toolError("rate limit request timed out")
        }

        if let error = resp["error"] as? [String: Any] {
            let msg = (error["message"] as? String) ?? "unknown error"
            let lowered = msg.lowercased()
            if lowered.contains("auth") || lowered.contains("login")
                || lowered.contains("unauthorized") || lowered.contains("401") {
                return .authError(msg)
            }
            return .toolError(msg)
        }

        guard let result = resp["result"] as? [String: Any],
              let limits = result["rateLimits"] as? [String: Any] else {
            return .toolError("unexpected response shape")
        }
        guard let primary = limits["primary"] as? [String: Any],
              let used = primary["usedPercent"] as? Double else {
            // Logged out accounts return an empty rateLimits object.
            return .authError("no rate limit data — are you logged in?")
        }

        var resets: Date?
        if let ts = primary["resetsAt"] as? Double {
            resets = Date(timeIntervalSince1970: ts)
        }
        var credits: String?
        if let c = limits["credits"] as? [String: Any],
           let balance = c["balance"] as? String, balance != "0" {
            credits = balance
        }
        return .success(Usage(remainingPercent: 100 - used,
                              resetsAt: resets,
                              credits: credits))
    }
}

// MARK: - Resize grip

/// Bottom-right resize grip: shows a resize cursor and resizes the window
/// proportionally, keeping the top-left corner fixed.
final class ResizeGripView: NSView {
    var minWidth: CGFloat = 240
    var maxWidth: CGFloat = 900
    var aspect: CGFloat = 340.0 / 130.0
    private var startFrame = NSRect.zero
    private var startMouse = NSPoint.zero

    override var mouseDownCanMoveWindow: Bool { false }

    override func resetCursorRects() {
        if #available(macOS 15.0, *) {
            addCursorRect(bounds, cursor: .frameResize(position: .bottomRight,
                                                       directions: .all))
        }
        // Older systems: no perfect public cursor for diagonal resize; the
        // visible grip lines still signal the affordance.
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.withAlphaComponent(0.35).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1.5
        for i in 1...3 {
            let off = CGFloat(i) * 5
            path.move(to: NSPoint(x: bounds.width - off, y: 3))
            path.line(to: NSPoint(x: bounds.width - 3, y: off))
        }
        path.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        guard let win = window else { return }
        startFrame = win.frame
        startMouse = NSEvent.mouseLocation
    }

    override func mouseDragged(with event: NSEvent) {
        guard let win = window else { return }
        let loc = NSEvent.mouseLocation
        let dx = loc.x - startMouse.x
        let dy = (startMouse.y - loc.y) * aspect
        var newW = startFrame.width + max(dx, dy)
        newW = min(max(newW, minWidth), maxWidth)
        let newH = newW / aspect
        win.setFrame(NSRect(x: startFrame.minX, y: startFrame.maxY - newH,
                            width: newW, height: newH), display: true)
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var panel: NSPanel!
    let percentLabel = NSTextField(labelWithString: "…")
    let remainingLabel = NSTextField(labelWithString: "")
    let detailLabel = NSTextField(labelWithString: "loading")
    let barFill = NSView()
    let barTrack = NSView()
    let grip = ResizeGripView()
    let loginButton = NSButton(title: "Log in with Codex", target: nil, action: nil)

    let defaultSize = NSSize(width: 340, height: 130)
    var aspect: CGFloat { defaultSize.width / defaultSize.height }
    let frameSaveKey = "CodexUsagePanelFrame"
    var authAlertShown = false
    var currentPercent: Double = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: defaultSize),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView, .resizable],
            backing: .buffered, defer: false
        )
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.contentAspectRatio = defaultSize
        panel.minSize = NSSize(width: 240, height: 240 / aspect)
        panel.maxSize = NSSize(width: 900, height: 900 / aspect)
        panel.delegate = self

        for b: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(b)?.isHidden = true
        }

        if let content = panel.contentView {
            content.wantsLayer = true
            content.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.88).cgColor
            content.layer?.cornerRadius = 18
            content.layer?.masksToBounds = true
        }

        if let saved = UserDefaults.standard.string(forKey: frameSaveKey) {
            var f = NSRectFromString(saved)
            f.size.height = f.size.width / aspect
            panel.setFrame(f, display: false)
            ensureOnScreen()
        } else {
            pinTopLeft()
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.ensureOnScreen() }

        percentLabel.textColor = .white
        remainingLabel.textColor = NSColor.white.withAlphaComponent(0.75)
        detailLabel.textColor = NSColor.white.withAlphaComponent(0.6)

        barTrack.wantsLayer = true
        barTrack.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.18).cgColor
        barFill.wantsLayer = true
        barTrack.addSubview(barFill)

        grip.aspect = aspect
        grip.minWidth = panel.minSize.width
        grip.maxWidth = panel.maxSize.width

        loginButton.target = self
        loginButton.action = #selector(loginPressed)
        loginButton.bezelStyle = .rounded
        loginButton.isHidden = true

        // Right-click menu: Refresh / Quit.
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Refresh Now", action: #selector(refreshPressed),
                                keyEquivalent: "r"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Codex Usage", action: #selector(quitPressed),
                                keyEquivalent: "q"))
        for item in menu.items { item.target = self }
        panel.contentView?.menu = menu

        panel.contentView?.addSubview(percentLabel)
        panel.contentView?.addSubview(remainingLabel)
        panel.contentView?.addSubview(barTrack)
        panel.contentView?.addSubview(detailLabel)
        panel.contentView?.addSubview(loginButton)
        panel.contentView?.addSubview(grip)
        layout()
        panel.orderFrontRegardless()

        refresh()
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.refresh()      // every 5 minutes
        }
    }

    // MARK: Layout — one scale factor, everything proportional to the default design.

    func layout() {
        guard let bounds = panel.contentView?.bounds else { return }
        let s = bounds.height / defaultSize.height
        let margin = 24 * s
        let contentWidth = bounds.width - margin * 2

        percentLabel.font = .monospacedSystemFont(ofSize: 44 * s, weight: .bold)
        let percentW = percentLabel.intrinsicContentSize.width
        percentLabel.frame = NSRect(x: margin, y: 58 * s, width: percentW + 8, height: 52 * s)

        remainingLabel.font = .systemFont(ofSize: 16 * s, weight: .medium)
        remainingLabel.frame = NSRect(x: margin + percentW + 12 * s, y: 62 * s,
                                      width: contentWidth - percentW - 12 * s,
                                      height: 22 * s)

        barTrack.frame = NSRect(x: margin, y: 36 * s, width: contentWidth, height: 14 * s)
        barTrack.layer?.cornerRadius = 7 * s
        barFill.frame = NSRect(x: 0, y: 0,
                               width: contentWidth * currentPercent / 100, height: 14 * s)
        barFill.layer?.cornerRadius = 7 * s

        detailLabel.font = .monospacedSystemFont(ofSize: 12 * s, weight: .regular)
        detailLabel.frame = NSRect(x: margin, y: 12 * s, width: contentWidth, height: 16 * s)

        let gripSize = 18 * s
        grip.frame = NSRect(x: bounds.width - gripSize - 4 * s, y: 4 * s,
                            width: gripSize, height: gripSize)
        grip.needsDisplay = true
        panel.invalidateCursorRects(for: grip)

        loginButton.frame = NSRect(x: margin, y: 36 * s, width: 180, height: 28)
    }

    func windowDidResize(_ notification: Notification) {
        layout()
        saveFrame()
    }

    func windowDidMove(_ notification: Notification) { saveFrame() }

    func saveFrame() {
        UserDefaults.standard.set(NSStringFromRect(panel.frame), forKey: frameSaveKey)
    }

    func pinTopLeft() {
        guard let screen = NSScreen.main else { return }
        let f = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: f.minX + 16, y: f.maxY - panel.frame.height - 16))
    }

    func ensureOnScreen() {
        let visible = NSScreen.screens.contains { $0.visibleFrame.intersects(panel.frame) }
        if !visible { pinTopLeft() }
    }

    // MARK: Data

    func refresh() {
        CodexClient.fetch { result in
            DispatchQueue.main.async { self.update(result) }
        }
    }

    func update(_ result: FetchResult) {
        switch result {
        case .success(let usage):
            authAlertShown = false
            loginButton.isHidden = true
            barTrack.isHidden = false
            remainingLabel.isHidden = false

            let pct = usage.remainingPercent
            currentPercent = pct
            percentLabel.stringValue = String(format: "%.0f%%", pct)
            remainingLabel.stringValue = "remaining"

            var detail = ""
            if let resets = usage.resetsAt {
                let fmt = DateFormatter()
                fmt.dateFormat = "EEE MMM d, h:mm a"
                detail = "resets \(fmt.string(from: resets))"
            }
            if let credits = usage.credits { detail += "   ·   \(credits) credits" }
            detailLabel.stringValue = detail

            let color: NSColor = pct > 50 ? .systemGreen
                               : pct > 20 ? .systemOrange : .systemRed
            barFill.layer?.backgroundColor = color.cgColor
            percentLabel.textColor = pct > 20 ? .white : .systemRed
            layout()

        case .authError:
            percentLabel.stringValue = "!"
            percentLabel.textColor = .systemRed
            remainingLabel.isHidden = true
            barTrack.isHidden = true
            loginButton.isHidden = false
            detailLabel.stringValue = "not logged in — run codex login"
            promptLoginOnce()

        case .toolError(let msg):
            // Keep last known values; surface the problem in the detail line.
            detailLabel.stringValue = msg
        }
    }

    func promptLoginOnce() {
        guard !authAlertShown else { return }
        authAlertShown = true
        let alert = NSAlert()
        alert.messageText = "Codex login required"
        alert.informativeText =
            "This widget reads usage via Codex CLI, which isn't logged in. "
            + "Run `codex login` to authenticate."
        alert.addButton(withTitle: "Open Terminal & Log In")
        alert.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { runCodexLogin() }
    }

    @objc func loginPressed() { runCodexLogin() }
    @objc func refreshPressed() { refresh() }
    @objc func quitPressed() { NSApp.terminate(nil) }

    func runCodexLogin() {
        let script = """
        tell application "Terminal"
            activate
            do script "codex login"
        end tell
        """
        if let osa = NSAppleScript(source: script) {
            var err: NSDictionary?
            osa.executeAndReturnError(&err)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            self?.authAlertShown = false
            self?.refresh()
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // no Dock icon
let delegate = AppDelegate()
app.delegate = delegate
app.run()
