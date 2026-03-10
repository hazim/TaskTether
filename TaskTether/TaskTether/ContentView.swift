//
//  ContentView.swift
//  TaskTether
//
//  Created by Hazim Sami on 10/03/2026.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var authManager = GoogleAuthManager()
    
    var body: some View {
        if authManager.isAuthenticated {
            MainView(authManager: authManager)
        } else {
            ConnectView(authManager: authManager)
        }
    }
}

// MARK: - Connect View (not yet authenticated)
struct ConnectView: View {
    @ObservedObject var authManager: GoogleAuthManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            
            // Header
            Text("TaskTether")
                .font(.headline)
                .fontWeight(.bold)
            
            Divider()
            
            // Description
            Text("Sync Apple Reminders with Google Tasks seamlessly.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            
            // Error message
            if let error = authManager.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            // Connect button
            Button {
                authManager.signIn()
            } label: {
                HStack {
                    if authManager.isAuthenticating {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                    Text(authManager.isAuthenticating ? "Connecting..." : "Connect Google Account")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(authManager.isAuthenticating)
            
            Divider()
            
            // Quit
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                HStack {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                    Text("Quit")
                }
            }
            .foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 260)
    }
}

// MARK: - Main View (authenticated)
struct MainView: View {
    @ObservedObject var authManager: GoogleAuthManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            
            // Header
            Text("TaskTether")
                .font(.headline)
                .fontWeight(.bold)
            
            Divider()
            
            // Service status
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Circle()
                        .fill(.green)
                        .frame(width: 8, height: 8)
                        .help("Reminders connected")
                    Text("Reminders")
                        .font(.caption)
                }
                HStack {
                    Circle()
                        .fill(.green)
                        .frame(width: 8, height: 8)
                        .help("Google Tasks connected")
                    Text("Google Tasks")
                        .font(.caption)
                }
            }
            
            // Last synced
            Text("Last synced: Never")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            // Sync Now
            Button {
                // sync logic coming soon
            } label: {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("Sync Now")
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
                }
                .help("Settings")
                .buttonStyle(.plain)
                
                Spacer()
                
                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                }
                .help("Quit")
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(width: 260)
    }
}
