//
//  TaskTetherApp.swift
//  TaskTether
//
//  Created by Hazim Sami on 10/03/2026.
//  Updated: 07/05/2026 — replaced MenuBarExtra (macOS 13+) with
//           NSStatusItem + NSPanel (available macOS 10.5+).
//           NSPanel has no beak/arrow and gives full position control:
//           the panel's right and top edges are pinned to the status item
//           so it always grows downward and leftward when expanding.
//

import SwiftUI
import AppKit
import Combine

// MARK: - App Entry Point

@main
struct TaskTetherApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Settings window — hosted by SwiftUI, opened via AppKit selector.
        // Environment objects are supplied from AppDelegate so the same
        // instances are shared with the panel content.
        Settings {
            SettingsView()
                .environmentObject(appDelegate.themeManager)
                .environmentObject(appDelegate.authManager)
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    // Requests the AppDelegate to close the menu bar panel.
    static let taskTetherHidePanel = Notification.Name("taskTetherHidePanel")
    // Posted by the Settings badge toggle so the AppDelegate refreshes the
    // menu bar item immediately instead of waiting for the next task sync.
    static let taskTetherBadgeSettingChanged = Notification.Name("taskTetherBadgeSettingChanged")
}

// MARK: - KeyablePanel
// borderless NSPanel.canBecomeKey returns false by default, which prevents:
//   - text fields from receiving keyboard focus (can't type tasks)
//   - NSApp.sendAction from traversing the right responder chain (settings broken)
// Overriding restores standard key-window behaviour while keeping the
// borderless, arrow-free appearance.

private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool  { true  }
    override var canBecomeMain: Bool { false }
}

// MARK: - AppDelegate

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    let themeManager:       ThemeManager
    let authManager:        GoogleAuthManager
    let remindersManager:   RemindersManager
    let googleTasksManager: GoogleTasksManager
    let syncEngine:         SyncEngine

    private var statusItem:   NSStatusItem?
    private var panel:        NSPanel?
    private var eventMonitor: Any?
    private var badgeCancellable: AnyCancellable?

    // Screen-space anchor: right edge of the status item button and the
    // bottom edge of the menu bar. These are stored when the panel first
    // opens and used by windowDidResize to keep the panel locked in place
    // as the SwiftUI layout changes width/height (compact ↔ expanded).
    private var anchorRight: CGFloat = 0
    private var anchorTop:   CGFloat = 0

    // MARK: init

    override init() {
        #if DEBUG
        // Line-buffer stdout so DEBUG prints reach a redirected log as they
        // happen instead of only at a clean exit.
        setvbuf(stdout, nil, _IOLBF, 0)
        #endif
        let theme  = ThemeManager()
        let auth   = GoogleAuthManager()
        let remind = RemindersManager()
        let google = GoogleTasksManager(authManager: auth)
        let engine = SyncEngine(
            remindersManager:   remind,
            googleTasksManager: google,
            authManager:        auth,
            themeManager:       theme
        )
        themeManager       = theme
        authManager        = auth
        remindersManager   = remind
        googleTasksManager = google
        syncEngine         = engine
        super.init()
    }

    // MARK: applicationDidFinishLaunching

    func applicationDidFinishLaunching(_ notification: Notification) {
        applyActivationPolicy()
        setupMenuBar()
        setupBadge()
        setupLaunchAtLoginDefault()

        // Posted by the Settings gear button — the panel must close before
        // the Settings window opens or its .popUpMenu level would cover it.
        NotificationCenter.default.addObserver(
            forName: .taskTetherHidePanel, object: nil, queue: .main
        ) { [weak self] _ in
            self?.hidePanel()
        }
    }

    // Launch at login defaults to ON. Re-registers on every launch (not just
    // the first) because SMAppService pins the bundle path at registration —
    // a user who first ran from Downloads and later moved the app to
    // /Applications would otherwise stay pointed at the stale path.
    // register() is idempotent, so this is a no-op once already correct.
    // Skips an ephemeral bundle path (DMG mount or Gatekeeper translocation),
    // where registering is pointless.
    private func setupLaunchAtLoginDefault() {
        guard LoginItemManager.isSupported else { return }
        if UserDefaults.standard.object(forKey: "launchAtLogin") == nil {
            UserDefaults.standard.set(true, forKey: "launchAtLogin")
        }
        guard UserDefaults.standard.bool(forKey: "launchAtLogin"),
              !LoginItemManager.isRunningFromEphemeralLocation else { return }
        do {
            try LoginItemManager.setEnabled(true)
        } catch {
            #if DEBUG
            print("LoginItemManager: failed to enable launch at login — \(error)")
            #endif
        }
    }

    private func applyActivationPolicy() {
        NSApp.setActivationPolicy(
            UserDefaults.standard.bool(forKey: "showInDock") ? .regular : .accessory
        )
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(
                systemSymbolName: "arrow.triangle.2.circlepath",
                accessibilityDescription: "TaskTether"
            )
            button.action = #selector(handleStatusItemClick)
            button.target = self
        }

        let hosting = NSHostingController(rootView:
            ContentView()
                .environmentObject(themeManager)
                .environmentObject(authManager)
                .environmentObject(remindersManager)
                .environmentObject(googleTasksManager)
                .environmentObject(syncEngine)
        )

        // KeyablePanel (NSPanel subclass) instead of NSPopover:
        //   - No triangular beak — clean flush appearance under the menu bar
        //   - Full position control — right/top edges stay pinned on resize
        //   - canBecomeKey = true enables text field focus and sendAction routing
        //   - borderless + nonactivatingPanel available from macOS 10.5
        let p = KeyablePanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.contentViewController = hosting
        p.isOpaque = false
        p.backgroundColor = .clear
        p.level = .popUpMenu
        p.hasShadow = true
        p.isMovable = false
        p.collectionBehavior = [.canJoinAllSpaces]
        p.delegate = self

        // Rounded corners — mask the content view layer so the system shadow
        // (computed from opaque pixels in a transparent window) follows the shape.
        p.contentView?.wantsLayer = true
        p.contentView?.layer?.cornerRadius = 10
        p.contentView?.layer?.masksToBounds = true

        panel = p
    }

    // MARK: - Menu Bar Badge

    // Subscribes to task changes and the Settings toggle so the badge stays
    // current without waiting for the panel to be opened.
    private func setupBadge() {
        badgeCancellable = syncEngine.$tasks
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateBadge() }

        NotificationCenter.default.addObserver(
            forName: .taskTetherBadgeSettingChanged, object: nil, queue: .main
        ) { [weak self] _ in
            self?.updateBadge()
        }

        updateBadge()
    }

    // Shows the count of incomplete top-level tasks next to the status item
    // icon, matching what the main task list displays (subtasks excluded).
    private func updateBadge() {
        guard let button = statusItem?.button else { return }

        let enabled = UserDefaults.standard.object(forKey: "showMenuBarBadge") as? Bool ?? false
        let count = syncEngine.tasks.filter { !$0.isCompleted && $0.parentGoogleId == nil }.count

        button.imagePosition = .imageLeading
        button.title = (enabled && count > 0) ? " \(count)" : ""
        statusItem?.length = button.title.isEmpty
            ? NSStatusItem.squareLength
            : NSStatusItem.variableLength
    }

    // MARK: - Toggle

    @objc private func handleStatusItemClick(_ sender: AnyObject?) {
        guard let p = panel else { return }
        p.isVisible ? hidePanel() : showPanel()
    }

    private func showPanel() {
        guard let p = panel,
              let button = statusItem?.button,
              let buttonWindow = button.window else { return }

        // Convert the status item button to screen coordinates.
        let buttonRectInWindow = button.convert(button.bounds, to: nil)
        let buttonScreenRect   = buttonWindow.convertToScreen(buttonRectInWindow)

        // Store the anchor corner — right edge of the button, bottom of the
        // menu bar. windowDidResize uses these to keep the panel locked.
        anchorRight = buttonScreenRect.maxX
        anchorTop   = buttonScreenRect.minY

        positionPanel()

        p.orderFrontRegardless()
        p.makeKey()
        NSApp.activate(ignoringOtherApps: true)

        // Dismiss on any click outside the panel (in another app or the
        // desktop). Clicks inside the panel are local events and do not
        // trigger the global monitor, so they are handled normally.
        eventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in self?.hidePanel() }
    }

    private func hidePanel() {
        panel?.orderOut(nil)
        if let m = eventMonitor { NSEvent.removeMonitor(m); eventMonitor = nil }
    }

    // Sets the panel origin so its right edge = anchorRight and its top
    // edge = anchorTop (flush with the bottom of the menu bar), then clamps
    // to keep the panel inside the visible screen area.
    private func positionPanel() {
        guard let p = panel, anchorRight > 0 else { return }

        let size = p.frame.size
        var origin = CGPoint(
            x: anchorRight - size.width,
            y: anchorTop   - size.height
        )

        if let screen = p.screen ?? NSScreen.main {
            let v = screen.visibleFrame
            origin.x = max(origin.x, v.minX + 4)
            origin.x = min(origin.x, v.maxX - size.width - 4)
            origin.y = max(origin.y, v.minY + 4)
        }

        p.setFrameOrigin(origin)
    }

    // MARK: - NSWindowDelegate

    // Called after every SwiftUI-driven resize (compact ↔ expanded, or when
    // the task list height changes). Re-snaps the panel so the right and top
    // edges stay pinned — the panel grows leftward and downward only.
    func windowDidResize(_ notification: Notification) {
        guard let p = panel, notification.object as? NSWindow === p else { return }
        positionPanel()
    }
}
