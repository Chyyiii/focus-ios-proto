import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("FOCUS")
                .font(.largeTitle.bold())
            Text("Прототип · сборка B1")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}
