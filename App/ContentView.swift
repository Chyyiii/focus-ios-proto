import SwiftUI

// B3: экран приложения — встроенный FOCUS в WKWebView. Диагностика видна только с аргументом запуска -focusDiagnostics.
struct ContentView: View {
    @ObservedObject var controller: FocusWebController
    private let showDiagnostics = ProcessInfo.processInfo.arguments.contains("-focusDiagnostics")

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()
            FocusWebView(controller: controller)
                .ignoresSafeArea(.container, edges: .bottom)
            if showDiagnostics {
                VStack(alignment: .leading, spacing: 2) {
                    Text("stored: \(controller.storedCount)")
                    ForEach(Array(controller.lines.enumerated()), id: \.offset) { item in
                        Text(item.element)
                    }
                }
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white)
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.75))
                .allowsHitTesting(false)
            }
        }
    }
}
