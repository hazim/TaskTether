//
//  LoginItemManager.swift
//  TaskTether
//
//  Wraps ServiceManagement's SMAppService for the sandboxed "Launch at
//  login" preference. SMAppService.mainApp is only available macOS 13+;
//  LaunchAgents / LSSharedFileList are not usable under the App Sandbox,
//  so macOS 12 simply reports the feature as unsupported and no-ops.
//

import Foundation
import ServiceManagement

enum LoginItemManager {

    /// True on macOS 13+, where SMAppService is available.
    static var isSupported: Bool {
        if #available(macOS 13, *) { return true }
        return false
    }

    /// Current registration state. Always false pre-macOS 13.
    static var isEnabled: Bool {
        guard #available(macOS 13, *) else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    /// Registers or unregisters the app as a login item. No-op pre-macOS 13.
    static func setEnabled(_ on: Bool) throws {
        guard #available(macOS 13, *) else { return }
        if on {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    /// True when running from a DMG mount (/Volumes/…) or a Gatekeeper
    /// translocation path (/…/AppTranslocation/…) — a quarantined app run
    /// straight from Downloads gets relaunched from a randomized read-only
    /// path, so registering (or reading status for) a login item there is
    /// meaningless: it does not reflect where the app will actually live.
    static var isRunningFromEphemeralLocation: Bool {
        let path = Bundle.main.bundleURL.path
        return path.hasPrefix("/Volumes/") || path.contains("/AppTranslocation/")
    }
}
