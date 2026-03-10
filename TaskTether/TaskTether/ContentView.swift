//
//  ContentView.swift
//  TaskTether
//
//  Created by Hazim Sami on 10/03/2026.
//

import SwiftUI

// MARK: - Status Dot Component

enum ConnectionStatus {
    case connected
    case syncing
    case error
    
    var color: Color {
        switch self {
        case .connected: return Color(red: 0.18, green: 0.80, blue: 0.44)
        case .syncing:   return Color(red: 0.95, green: 0.61, blue: 0.07)
        case .error:     return Color(red: 0.91, green: 0.30, blue: 0.24)
        }
    }
    
    var label: String {
        switch self {
        case .connected: return "Connected"
        case .syncing:   return "Syncing"
        case .error:     return "Error"
        }
    }
}

struct StatusDot: View {
    let status: ConnectionStatus
    
    var body: some View {
        ZStack {
            // Outer glow — very soft
            Circle()
                .fill(status.color.opacity(0.15))
                .frame(width: 18, height: 18)
            // Mid glow
            Circle()
                .fill(status.color.opacity(0.30))
                .frame(width: 13, height: 13)
            // Core dot
            Circle()
                .fill(status.color)
                .frame(width: 7, height: 7)
        }
    }
}

// MARK: - Content View

struct ContentView: View {
    @StateObject private var authManager = GoogleAuthManager()
    @StateObject private var remindersManager = RemindersManager()
    
    var body: some View {
            Group {
                if authManager.isAuthenticated {
                    MainView(authManager: authManager, remindersManager: remindersManager)
                } else {
                    ConnectView(authManager: authManager)
                }
            }
            .onAppear {
                remindersManager.requestAccess()
            }
        }
}

// MARK: - Connect View

struct ConnectView: View {
    @ObservedObject var authManager: GoogleAuthManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            
            Text("TaskTether")
                .font(.system(size: 14, weight: .semibold))
            
            Divider()
            
            Text("Sync Apple Reminders with Google Tasks seamlessly.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            
            if let error = authManager.errorMessage {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Button {
                authManager.signIn()
            } label: {
                HStack {
                    if authManager.isAuthenticating {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                    Text(authManager.isAuthenticating ? "Connecting..." : "Connect Google Account")
                        .font(.system(size: 12, weight: .medium))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(authManager.isAuthenticating)
            
            Divider()
            
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 12))
                    Text("Quit")
                        .font(.system(size: 12))
                }
            }
            .foregroundStyle(.secondary)
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(width: 260)
    }
}

// MARK: - Main View

struct MainView: View {
    @ObservedObject var authManager: GoogleAuthManager
    @ObservedObject var remindersManager: RemindersManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            
            // Header
            Text("TaskTether")
                .font(.system(size: 14, weight: .semibold))
            
            Divider()
            
            // Service status
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    StatusDot(status: .connected)
                        .help("Reminders: Connected")
                    Text("Reminders")
                        .font(.system(size: 12))
                }
                HStack(spacing: 8) {
                    StatusDot(status: .connected)
                        .help("Google Tasks: Connected")
                    Text("Google Tasks")
                        .font(.system(size: 12))
                }
            }
            
            // Last synced
            Text("Last synced: Never")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            
            // Sync Now
            Button {
                // sync logic coming soon
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 12))
                    Text("Sync Now")
                        .font(.system(size: 12, weight: .medium))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            
            Divider()
            
            // Bottom bar
            HStack {
                Button {
                    // settings coming soon
                } label: {
                    Image(systemName: "gear")
                        .font(.system(size: 13))
                }
                .help("Settings")
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                
                Spacer()
                
                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 13))
                }
                .help("Quit TaskTether")
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(width: 260)
    }
}
