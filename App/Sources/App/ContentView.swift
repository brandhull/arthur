import SwiftUI

struct ContentView: View {
    @State private var showingSplash = true

    // AgendaView stays mounted underneath at all times — including while
    // SplashView is showing on top — instead of the previous if/else swap,
    // which destroyed and recreated AgendaView (and its TaskStore/
    // DocumentStore) every single time. That meant every splash *replay*
    // (the brain-icon tap, not just cold launch) silently wiped any
    // in-progress, unsaved Rocks/Reflection edit sitting in that torn-down
    // view's own @State, and forced a full refetch no matter how recently
    // the app had already loaded — the fresh TaskStore had no memory of
    // that. SplashView's own opaque background fully covers AgendaView
    // while it's up, so the visible behavior on cold launch is unchanged;
    // the difference is AgendaView's initial `.task` fetch now runs
    // concurrently with the splash's ~5s hold instead of only starting
    // after it, and a replay just fades the same still-alive screen back
    // into view rather than reconstructing it.
    var body: some View {
        ZStack {
            AgendaView(onReplaySplash: { showingSplash = true })
            if showingSplash {
                SplashView { showingSplash = false }
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: showingSplash)
    }
}
