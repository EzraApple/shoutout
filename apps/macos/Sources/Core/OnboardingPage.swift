public enum OnboardingPage: String, CaseIterable, Sendable {
    case welcome
    case howItWorks
    case permissions

    public static func restore(savedPage: String, legacyStep: Int) -> Self {
        if let page = Self(rawValue: savedPage) {
            return page
        }
        // Every screen after the old welcome page was part of permission/model setup.
        return legacyStep > 0 ? .permissions : .welcome
    }
}
