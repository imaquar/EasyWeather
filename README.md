# EasyWeather

EasyWeather is a minimal iOS weather app focused on one thing: clear day-to-day comparison.

## What it does

- Compares temperature trends with simple text:
  - `today is ... as/than yesterday`
  - `tomorrow will be ... as/than today`
- Supports two modes: `today` and `tomorrow`
- Shows 4 fixed periods for the selected day:
  - `morning`, `noon`, `evening`, `night`
- Uses Celsius only
- Lets you switch theme (light/dark) in Settings
- Lets you search and select city with live suggestions
- Automatically refreshes weather in the app

## Widget

Widget extension includes:

- **Small widget**: main 3 comparison lines + compact weather info
- **Medium widget**: `morning/noon/evening/night` rows with icon + temperature
- Periodic timeline refresh (about every 30 minutes)
- Uses shared snapshot via App Group

## Data sources

- Primary: **WeatherKit** (if enabled in app config and available)
- Fallback: **Open-Meteo** (no API key)

By default, project is configured to use Open-Meteo unless `UseWeatherKit` is explicitly enabled in app config.

## Stack

- Swift + SwiftUI
- MVVM
- async/await
- URLSession + Codable
- CoreLocation + MapKit geocoding APIs
- UserDefaults cache (TTL 30 min)

## Requirements

- Xcode 26.3+
- iOS deployment target: 26.2+
- Apple Developer account for real device installation

## Run locally

1. Open `EasyWeather.xcodeproj` in Xcode.
2. Select scheme **EasyWeather**.
3. Choose Simulator or your iPhone.
4. Build and Run.

## Signing and capabilities checklist

For running on your own team/bundle:

1. In Xcode, set your Team for both targets:
   - `EasyWeather`
   - `EasyWeatherWidgetExtension`
2. Keep App Group consistent in both entitlements:
   - `EasyWeather/EasyWeather.entitlements`
   - `EasyWeatherWidgetExtension/EasyWeatherWidgetExtension.entitlements`
3. If you change bundle id, also verify widget host bundle id in:
   - `Configs/EasyWeatherWidgetExtension-Info.plist`
   - key: `WKAppBundleIdentifier`

## Notes

- If location permission is denied, app shows an explicit state and allows selecting a city manually.
- Widget location requires `NSWidgetWantsLocation = true` in widget Info.plist (already set).
- If WeatherKit entitlement/auth is not available, app falls back to Open-Meteo automatically.
