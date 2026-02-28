import Foundation
import MapKit

@MainActor
final class CitySearchService: NSObject, MKLocalSearchCompleterDelegate {
    private let completer = MKLocalSearchCompleter()
    private var continuation: CheckedContinuation<[String], Never>?

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
    }

    func searchCities(matching query: String) async -> [String] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedQuery.count >= 2 else {
            completer.queryFragment = ""
            return []
        }

        return await withCheckedContinuation { continuation in
            self.continuation?.resume(returning: [])
            self.continuation = continuation
            completer.queryFragment = trimmedQuery
        }
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        guard let continuation else {
            return
        }

        self.continuation = nil
        continuation.resume(returning: normalizedSuggestions(from: completer.results))
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        guard let continuation else {
            return
        }

        self.continuation = nil
        continuation.resume(returning: [])
    }

    private func normalizedSuggestions(from results: [MKLocalSearchCompletion]) -> [String] {
        var seen: Set<String> = []
        var suggestions: [String] = []

        for result in results {
            let title = result.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else {
                continue
            }

            let subtitle = result.subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = subtitle.isEmpty ? title : "\(title), \(subtitle)"
            let key = value.lowercased()

            guard seen.insert(key).inserted else {
                continue
            }

            suggestions.append(value)
            if suggestions.count == 10 {
                break
            }
        }

        return suggestions
    }
}
