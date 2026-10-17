import SwiftUI

@main
struct OXStompApp: App {
    var body: some Scene {
        WindowGroup {
            StompWebView()
                .background(Color(red: 0.08, green: 0.07, blue: 0.06))
                .preferredColorScheme(.dark)
        }
    }
}
