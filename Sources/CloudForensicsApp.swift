// Sources/CloudForensicsApp.swift
import SwiftUI

@main
struct CloudForensicsApp: App {
    @StateObject private var store = ForensicsStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
    }
}
