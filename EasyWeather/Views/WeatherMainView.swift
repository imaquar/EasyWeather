import SwiftUI

struct WeatherMainView: View {
    @ObservedObject var viewModel: WeatherViewModel
    let onOpenSettings: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            backgroundColor
                .ignoresSafeArea()

            VStack(spacing: 18) {
                topBar

                if viewModel.displayState != .content {
                    Spacer(minLength: 0)
                }

                Group {
                    switch viewModel.displayState {
                    case .loading:
                        loadingView
                    case .permissionDenied:
                        PermissionView(
                            onOpenAppSettings: viewModel.openSettings,
                            onOpenInAppSettings: onOpenSettings
                        )
                    case .error:
                        ErrorView(message: viewModel.errorMessage, retryAction: viewModel.retryTapped)
                    case .unavailable:
                        Text("Weather data unavailable.")
                            .font(.system(.headline, design: .default, weight: .medium))
                    case .content:
                        contentView
                    }
                }
                .frame(maxWidth: .infinity)

                if viewModel.displayState != .content {
                    Spacer(minLength: 0)
                }

                if viewModel.isOffline {
                    Text("Offline")
                        .font(.system(.caption, design: .default, weight: .medium))
                        .foregroundStyle(.orange)
                }

                modeBar
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .task {
            viewModel.loadInitialWeather()
        }
    }

    private var topBar: some View {
        HStack {
            Text(viewModel.cityTitle)
                .font(.system(.title, design: .default, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer()

            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
                    .font(.system(.title3, design: .default, weight: .medium))
            }
            .buttonStyle(.glass)
            .tint(.primary)
            .accessibilityLabel("Open settings")
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Fetching weather...")
                .font(.system(.headline, design: .default, weight: .medium))
        }
    }

    private var contentView: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 56)

            VStack(spacing: 8) {
                Text(viewModel.comparisonLineOne)
                    .font(.system(.title2, design: .default, weight: .medium))

                Text(viewModel.comparisonKeyword)
                    .font(.system(size: 56, weight: .medium, design: .default))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)

                Text(viewModel.comparisonLineThree)
                    .font(.system(.title2, design: .default, weight: .medium))
            }
            .padding(.bottom, 12)

            Spacer(minLength: 44)

            VStack(spacing: 10) {
                ForEach(viewModel.periodRows) { row in
                    HStack(spacing: 12) {
                        Text(row.label)
                            .font(.system(.headline, design: .default, weight: .medium))

                        Spacer()

                        Text("\(Int(row.temperatureCelsius.rounded()))°C")
                            .font(.system(.headline, design: .default, weight: .medium))

                        Image(systemName: IconMapper.symbolName(for: row.condition))
                            .font(.system(.headline, design: .default, weight: .medium))
                            .frame(width: 24, height: 24, alignment: .center)
                            .accessibilityLabel("Condition \(row.condition.displayName)")
                    }
                    .frame(height: 28)
                }
            }
            .padding(.bottom, 6)
        }
        .contentShape(Rectangle())
        .gesture(modeSwipeGesture)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var modeBar: some View {
        Picker("Mode", selection: $viewModel.selectedMode) {
            Text("today").tag(ComparisonMode.today)
            Text("tomorrow").tag(ComparisonMode.tomorrow)
        }
        .pickerStyle(.segmented)
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? .black : .white
    }

    private var modeSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { value in
                let horizontalShift = value.translation.width
                let verticalShift = abs(value.translation.height)

                guard abs(horizontalShift) > 40, verticalShift < 80 else {
                    return
                }

                if horizontalShift < 0 {
                    viewModel.selectedMode = .tomorrow
                } else {
                    viewModel.selectedMode = .today
                }
            }
    }
}
