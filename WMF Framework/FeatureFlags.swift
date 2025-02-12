import Foundation

public struct FeatureFlags {

    public static var needsNewTalkPage: Bool {
        return true
    }

    public static var watchlistEnabled: Bool {
        return true
    }
    
    public static var donorExperienceImprovementsEnabled: Bool {
        #if WMF_STAGING
        return true
        #else
        return false
        #endif
    }
}
