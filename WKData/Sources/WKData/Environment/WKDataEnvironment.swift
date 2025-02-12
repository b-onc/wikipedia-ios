import Foundation

public struct WKAppData {
    let appLanguages: [WKLanguage]
    
    public init(appLanguages: [WKLanguage]) {
        self.appLanguages = appLanguages
    }
}

public final class WKDataEnvironment: ObservableObject {

	public static let current = WKDataEnvironment()
    
    public var serviceEnvironment: WKServiceEnvironment = .production

    @Published public var appData = WKAppData(appLanguages: [])
    
    public var mediaWikiService: WKService?
    public var basicService: WKService? = WKBasicService()
    
    public internal(set) var userDefaultsStore: WKKeyValueStore? = WKUserDefaultsStore()
    public var sharedCacheStore: WKKeyValueStore?
}
