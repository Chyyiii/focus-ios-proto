import WidgetKit
import SwiftUI

struct PlaceholderEntry: TimelineEntry {
    let date: Date
}

struct PlaceholderProvider: TimelineProvider {
    func placeholder(in context: Context) -> PlaceholderEntry {
        PlaceholderEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (PlaceholderEntry) -> Void) {
        completion(PlaceholderEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PlaceholderEntry>) -> Void) {
        completion(Timeline(entries: [PlaceholderEntry(date: Date())], policy: .never))
    }
}

struct FocusWidgetView: View {
    let entry: PlaceholderEntry

    var body: some View {
        Text("FOCUS")
            .font(.headline)
    }
}

struct FocusPlaceholderWidget: Widget {
    let kind = "FocusPlaceholder"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PlaceholderProvider()) { entry in
            FocusWidgetView(entry: entry)
        }
        .configurationDisplayName("FOCUS")
        .description("Заглушка B1")
        .supportedFamilies([.systemSmall])
    }
}
