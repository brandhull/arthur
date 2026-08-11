import SwiftUI
import ArthurKit

/// Startup screen — shows one quote from Brandon's Seneca commonplace-book
/// Baserow table, fading in, holding, then fading out. Replaces the earlier
/// fixed "Be Grateful."-style phrase cycle; those statements aren't gone,
/// they're just rows in Seneca now, in rotation with everything else he's
/// saved there. Tapping the title's brain icon re-triggers this same view
/// (see AgendaView/ContentView), and because SenecaStore.advance() moves
/// the rotation pointer forward every time this appears, that tap doubles
/// as "shuffle to the next quote" with no special-casing needed here.
struct SplashView: View {
    /// Shown only before Seneca has ever been configured/synced — a
    /// same-spirit bootstrap default, not part of the general rotation
    /// anymore (SenecaStore never produces id <= 0, so this can't collide
    /// with a real quote).
    static let fallback = SenecaQuote(id: -1, text: "Be Grateful.", author: nil)

    @State private var quote: SenecaQuote = SplashView.fallback
    @State private var opacity: Double = 0
    let onFinished: () -> Void

    var body: some View {
        ZStack {
            // Always dark + grey text, regardless of the device's actual
            // light/dark setting — reads better at any hour, per Brandon's
            // request, rather than flipping to light-navy-on-grey in the
            // daytime. Reads the saved dark style directly rather than
            // hardcoding Charcoal — this view exists before AgendaView's
            // TaskStore does, so it can't just read store.config.
            Theme.background(.dark).ignoresSafeArea()
            VStack(spacing: 14) {
                Text(quote.text)
                    .font(Theme.serif(24, weight: .medium))
                    .foregroundStyle(Theme.primary(.dark))
                    .multilineTextAlignment(.center)
                    // No lineLimit — wraps to however many lines it needs at
                    // the given width (capped at 480pt below), so it reads
                    // correctly on any screen, narrow iPhone through wide
                    // iPad/Mac. Deliberately NOT paired with a lineLimit +
                    // minimumScaleFactor "shrink to fit" combo — tried that
                    // for unusually long quotes, but without a bounded frame
                    // height to shrink against, SwiftUI just truncates with
                    // "…" at the line limit instead of scaling down, which
                    // silently loses part of the quote. That's worse than
                    // the rare case this was meant to guard against, so
                    // plain unlimited wrapping wins here.
                    .fixedSize(horizontal: false, vertical: true)
                if let author = quote.author, !author.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text(author)
                        .font(Theme.serif(15, weight: .regular))
                        .italic()
                        // NOT Theme.secondaryText(.dark) — that resolves to
                        // UIColor.secondaryLabel/NSColor.secondaryLabelColor,
                        // which are *dynamic* system colors that ignore the
                        // .dark argument entirely and resolve against the
                        // device's real light/dark setting. On an actual
                        // light-mode system that made this text a dark
                        // gray, invisible against this view's always-dark
                        // forced background. Theme.darkText is a concrete,
                        // non-dynamic color, so it stays correct regardless
                        // of the real system appearance — same fix pattern
                        // as Theme.primary(.dark) just above it.
                        .foregroundStyle(Theme.darkText.opacity(0.65))
                }
            }
            .frame(maxWidth: 480)
            .padding(.horizontal, 40)
            .opacity(opacity)
        }
        .task {
            let config = Config.load()
            let shown = await SenecaStore.shared.currentQuote() ?? Self.fallback
            quote = shown
            await SenecaStore.shared.advance()

            withAnimation(.easeInOut(duration: 0.5)) { opacity = 1 }
            // 4.1s hold — combined with the 0.5s fade-in and 0.4s fade-out
            // below, the quote is actually on screen for ~5s total, per
            // Brandon's request to have enough time to read a longer quote.
            try? await Task.sleep(nanoseconds: 4_100_000_000)
            withAnimation(.easeInOut(duration: 0.4)) { opacity = 0 }
            try? await Task.sleep(nanoseconds: 420_000_000)

            // Detached and unawaited — a slow network shouldn't hold up
            // dismissing the splash. Next launch (or next shuffle) benefits
            // from whatever this finds; this launch doesn't wait on it.
            Task.detached {
                await SenecaStore.shared.markShown(shown, config: config)
                await SenecaStore.shared.refillIfNeeded(config: config)
            }

            onFinished()
        }
    }
}
