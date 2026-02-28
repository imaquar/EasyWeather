import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: WeatherViewModel
    @Binding var isDarkMode: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isCityFieldFocused: Bool

    var body: some View {
        ZStack {
            backgroundColor
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 14) {
                    appearanceCard
                    citySearchCard
                }
                .padding(20)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        .preferredColorScheme(isDarkMode ? .dark : .light)
    }

    private var appearanceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Appearance")
                .font(.system(.headline, design: .default, weight: .medium))

            Picker("Theme", selection: $isDarkMode) {
                Text("Light").tag(false)
                Text("Dark").tag(true)
            }
            .pickerStyle(.segmented)
            .tint(colorScheme == .dark ? .white : .black)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var citySearchCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("City")
                .font(.system(.headline, design: .default, weight: .medium))

            TextField("Start typing a city", text: $viewModel.citySearchQuery)
                .textInputAutocapitalization(.words)
                .disableAutocorrection(true)
                .submitLabel(.search)
                .onSubmit {
                    viewModel.useTypedCityFromSettings()
                }
                .focused($isCityFieldFocused)
                .font(.system(.body, design: .default, weight: .medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .onChange(of: viewModel.citySearchQuery) { _, _ in
                    viewModel.citySearchQueryChanged()
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        isCityFieldFocused = true
                    }
                }

            if !viewModel.citySuggestions.isEmpty {
                VStack(spacing: 8) {
                    ForEach(viewModel.citySuggestions, id: \.self) { suggestion in
                        Button {
                            withAnimation(.smooth(duration: 0.22)) {
                                viewModel.selectCitySuggestion(suggestion)
                            }
                        } label: {
                            HStack {
                                Text(suggestion)
                                    .font(.system(.body, design: .default, weight: .medium))
                                    .foregroundStyle(.primary)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .glassEffectTransition(.materialize)
                        .id("\(suggestion)-\(colorScheme == .dark ? "dark" : "light")")
                    }
                }
                .id(colorScheme == .dark ? "suggestions-dark" : "suggestions-light")
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if !viewModel.citySearchStatusMessage.isEmpty {
                Text(viewModel.citySearchStatusMessage)
                    .font(.system(.caption, design: .default, weight: .medium))
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? .black : .white
    }
}
