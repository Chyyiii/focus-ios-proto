import SwiftUI

@main
struct FocusProtoApp: App {
    @StateObject private var controller = FocusWebController()

    var body: some Scene {
        WindowGroup {
            ContentView(controller: controller)
                .onOpenURL { url in controller.handleOpenURL(url) }
        }
    }
}
