import Foundation

enum Config {
    /// Base URL of the Jarvis API, injected via xcconfig → Info.plist.
    /// Debug → http://localhost:3000, Release → the Vercel deployment.
    static var apiBaseURL: URL {
        guard
            let raw = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String,
            let url = URL(string: raw), url.scheme != nil
        else {
            fatalError("API_BASE_URL missing or invalid in Info.plist. Check Config/*.xcconfig")
        }
        return url
    }
}
