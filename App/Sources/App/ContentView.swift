import SwiftUI

struct ContentView: View {
    @State private var showingSplash = true

    // AgendaView stays mounted underneath at all times, including while
    // SplashView is showing on top, rather than only being constructed once
    // showingSplash turns false — SplashView's own opaque background fully
    // covers it either way, so the visible behavior is unchanged, but
    // AgendaView's initial `.task` fetch now runs concurrently with the
    // splash's ~5s hold instead of only starting after it.
    var body: some View {
        ZStack {
            AgendaView()
            if showingSplash {
                SplashView { showingSplash = false }
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: showingSplash)
    }
}
