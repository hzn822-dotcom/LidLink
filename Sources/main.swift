// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 hzn822-dotcom and LidLink contributors

import AppKit
import Foundation
import ServiceManagement

private enum AppInfo {
    static let helperPath = "/Library/PrivilegedHelperTools/com.codex.lidlink-helper"
    static let daemonPath = "/Library/LaunchDaemons/com.codex.lidlink.plist"
    static let daemonLabel = "com.codex.lidlink"
}

private struct SystemState {
    let onAC: Bool
    let lidClosed: Bool
    let sleepDisabled: Bool
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let statusMenu = NSMenu()
    private let statusLineItem = NSMenuItem(title: "正在读取状态…", action: nil, keyEquivalent: "")
    private let enableItem = NSMenuItem(title: "接电时允许合盖在线", action: nil, keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "登录时启动", action: nil, keyEquivalent: "")
    private let helperItem = NSMenuItem(title: "安装系统助手…", action: nil, keyEquivalent: "")
    private let uninstallItem = NSMenuItem(title: "卸载系统助手并恢复睡眠…", action: nil, keyEquivalent: "")
    private var timer: Timer?
    private var state = SystemState(onAC: false, lidClosed: false, sleepDisabled: false)
    private var launchAtLoginState = false

    private var configURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.codex.lidlink", isDirectory: true)
            .appendingPathComponent("enabled")
    }

    private var desiredEnabled: Bool {
        (try? String(contentsOf: configURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)) == "1"
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        ensureConfigExists()
        statusItem.autosaveName = "com.codex.lidlink.statusItem"

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "laptopcomputer", accessibilityDescription: "盒盖在线")
            button.image?.isTemplate = true
            button.title = ""
        }

        launchAtLoginState = launchAtLoginEnabled
        buildMenu()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
    }

    private func ensureConfigExists() {
        let directory = configURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: configURL.path) {
            try? "0\n".write(to: configURL, atomically: true, encoding: .utf8)
        }
    }

    private func refresh() {
        state = readSystemState()
        updateStatusIcon()
        updateMenu()
    }

    private func updateStatusIcon() {
        let active = desiredEnabled && state.onAC && state.sleepDisabled
        let symbol = active ? "laptopcomputer.and.arrow.down" : "laptopcomputer"
        let fallback = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "盒盖在线")
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "盒盖在线") ?? fallback
        statusItem.button?.image?.isTemplate = true
    }

    private func buildMenu() {
        statusLineItem.isEnabled = false
        statusMenu.addItem(statusLineItem)
        statusMenu.addItem(.separator())

        enableItem.target = self
        enableItem.action = #selector(toggleEnabled)
        statusMenu.addItem(enableItem)

        loginItem.target = self
        loginItem.action = #selector(toggleLaunchAtLogin)
        statusMenu.addItem(loginItem)

        statusMenu.addItem(.separator())

        let screenOff = NSMenuItem(title: "立即关闭屏幕", action: #selector(turnDisplayOff), keyEquivalent: "d")
        screenOff.target = self
        statusMenu.addItem(screenOff)

        let sharing = NSMenuItem(title: "打开“共享”设置…", action: #selector(openSharingSettings), keyEquivalent: "")
        sharing.target = self
        statusMenu.addItem(sharing)

        statusMenu.addItem(.separator())

        helperItem.target = self
        helperItem.action = #selector(installHelper)
        statusMenu.addItem(helperItem)

        uninstallItem.target = self
        uninstallItem.action = #selector(uninstallHelper)
        statusMenu.addItem(uninstallItem)

        statusMenu.addItem(.separator())
        let quit = NSMenuItem(title: "退出盒盖在线", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        statusMenu.addItem(quit)

        statusItem.menu = statusMenu
    }

    private func updateMenu() {
        statusLineItem.title = statusText
        enableItem.state = desiredEnabled ? .on : .off
        loginItem.state = launchAtLoginState ? .on : .off
        helperItem.title = helperInstalled ? "修复系统助手…" : "安装系统助手…"
        uninstallItem.isHidden = !helperInstalled
    }

    private var statusText: String {
        if !helperInstalled { return "未安装系统助手" }
        if !desiredEnabled { return "已关闭 · 正常睡眠" }
        if !state.onAC { return "使用电池 · 正常睡眠" }
        if state.sleepDisabled { return state.lidClosed ? "接通电源 · 已合盖在线" : "接通电源 · 可合盖在线" }
        return "正在应用电源策略…"
    }

    private var helperInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: AppInfo.helperPath)
            && FileManager.default.fileExists(atPath: AppInfo.daemonPath)
    }

    private var launchAtLoginEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    @objc private func toggleEnabled() {
        if !desiredEnabled && !helperInstalled {
            guard performHelperInstall() else { return }
        }
        setDesiredEnabled(!desiredEnabled)
        refresh()
    }

    private func setDesiredEnabled(_ enabled: Bool) {
        ensureConfigExists()
        do {
            try (enabled ? "1\n" : "0\n").write(to: configURL, atomically: true, encoding: .utf8)
            _ = run("/bin/launchctl", ["kickstart", "-k", "system/\(AppInfo.daemonLabel)"])
        } catch {
            showError("无法保存设置", detail: error.localizedDescription)
        }
    }

    @objc private func toggleLaunchAtLogin() {
        guard #available(macOS 13.0, *) else { return }
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            showError("无法修改登录启动", detail: error.localizedDescription + "\n\n请先把“盒盖在线.app”放入“应用程序”文件夹后再试。")
        }
        launchAtLoginState = launchAtLoginEnabled
        refresh()
    }

    @objc private func turnDisplayOff() {
        _ = run("/usr/bin/pmset", ["displaysleepnow"])
    }

    @objc private func openSharingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Sharing-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func installHelper() {
        if performHelperInstall() {
            showInfo("系统助手已安装", detail: "现在可以开启“接电时允许合盖在线”。拔掉电源后，Mac 会自动恢复正常睡眠。")
            refresh()
        }
    }

    private func performHelperInstall() -> Bool {
        guard let helperSource = Bundle.main.path(forResource: "lidlink-helper", ofType: "sh"),
              let daemonSource = Bundle.main.path(forResource: "com.codex.lidlink", ofType: "plist") else {
            showError("安装文件不完整", detail: "请重新下载或重新构建 App。")
            return false
        }

        let commands = [
            "/bin/launchctl bootout system/\(AppInfo.daemonLabel) >/dev/null 2>&1 || true",
            "/bin/mkdir -p /Library/PrivilegedHelperTools /Library/LaunchDaemons",
            "/bin/cp \(shellQuote(helperSource)) \(shellQuote(AppInfo.helperPath))",
            "/bin/cp \(shellQuote(daemonSource)) \(shellQuote(AppInfo.daemonPath))",
            "/usr/sbin/chown root:wheel \(shellQuote(AppInfo.helperPath)) \(shellQuote(AppInfo.daemonPath))",
            "/bin/chmod 755 \(shellQuote(AppInfo.helperPath))",
            "/bin/chmod 644 \(shellQuote(AppInfo.daemonPath))",
            "/bin/launchctl bootstrap system \(shellQuote(AppInfo.daemonPath))"
        ].joined(separator: " && ")

        return runAsAdministrator(commands)
    }

    @objc private func uninstallHelper() {
        let alert = NSAlert()
        alert.messageText = "卸载系统助手？"
        alert.informativeText = "这会恢复正常合盖睡眠，并移除后台助手。App 本身不会被删除。"
        alert.addButton(withTitle: "卸载")
        alert.addButton(withTitle: "取消")
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        setDesiredEnabled(false)
        let commands = [
            "/usr/bin/pmset -a disablesleep 0",
            "/bin/launchctl bootout system/\(AppInfo.daemonLabel) >/dev/null 2>&1 || true",
            "/bin/rm -f \(shellQuote(AppInfo.helperPath)) \(shellQuote(AppInfo.daemonPath))"
        ].joined(separator: " && ")

        if runAsAdministrator(commands) {
            refresh()
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func readSystemState() -> SystemState {
        let battery = run("/usr/bin/pmset", ["-g", "batt"]).output
        let pm = run("/usr/bin/pmset", ["-g"]).output
        let io = run("/usr/sbin/ioreg", ["-r", "-k", "AppleClamshellState", "-d", "4"]).output
        return SystemState(
            onAC: battery.contains("AC Power"),
            lidClosed: io.contains("\"AppleClamshellState\" = Yes"),
            sleepDisabled: pm.range(of: #"SleepDisabled\s+1"#, options: .regularExpression) != nil
        )
    }

    private func runAsAdministrator(_ shellCommand: String) -> Bool {
        let escaped = shellCommand
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"\(escaped)\" with administrator privileges"
        let result = run("/usr/bin/osascript", ["-e", script])
        if result.status != 0 {
            if !result.output.contains("User canceled") && !result.output.contains("-128") {
                showError("管理员操作失败", detail: result.output)
            }
            return false
        }
        return true
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func run(_ executable: String, _ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
        } catch {
            return (-1, error.localizedDescription)
        }
    }

    private func showError(_ message: String, detail: String) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = message
        alert.informativeText = detail
        alert.runModal()
    }

    private func showInfo(_ message: String, detail: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = message
        alert.informativeText = detail
        alert.runModal()
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
