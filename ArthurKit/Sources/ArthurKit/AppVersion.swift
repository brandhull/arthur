import Foundation

/// The running app's version, read from its own Info.plist so Settings and
/// ArthurBar's menu can show exactly which build is installed on a device.
/// `short` is MARKETING_VERSION (see VERSIONING.md); `build` is the git
/// commit count stamped in at build time.
public enum AppVersion {
    public static var short: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    public static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }

    /// e.g. "1.0.0 (66)"
    public static var display: String { "\(short) (\(build))" }
}
