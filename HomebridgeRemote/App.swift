import SwiftUI

@main
struct HomebridgeRemoteApp: App {
    @State private var hub = Hub()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(hub)
        }
    }
}
