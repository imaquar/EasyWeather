import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = WeatherViewModel()
    @AppStorage("easyWeather.isDarkMode") private var isDarkMode = false
    @State private var isSettingsPresented = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            WeatherMainView(viewModel: viewModel) {
                isSettingsPresented = true
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $isSettingsPresented) {
                NavigationStack {
                    SettingsView(viewModel: viewModel, isDarkMode: $isDarkMode)
                }
                .preferredColorScheme(isDarkMode ? .dark : .light)
            }
        }
        .preferredColorScheme(isDarkMode ? .dark : .light)
        .environment(\.font, .system(.body, design: .default, weight: .medium))
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                viewModel.appBecameActive()
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15 * 60 * 1_000_000_000)
                viewModel.autoRefreshIfNeeded()
            }
        }
    }
}
