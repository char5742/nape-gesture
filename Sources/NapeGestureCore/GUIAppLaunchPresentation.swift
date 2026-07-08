import Foundation

public struct GUIAppLaunchPresentation: Equatable, Sendable {
    public var activationPolicy: String
    public var opensSettingsWindowOnLaunch: Bool
    public var reopensSettingsWindowFromDock: Bool
    public var keepsStatusMenu: Bool
    public var bundleLSUIElement: Bool

    public init(
        activationPolicy: String,
        opensSettingsWindowOnLaunch: Bool,
        reopensSettingsWindowFromDock: Bool,
        keepsStatusMenu: Bool,
        bundleLSUIElement: Bool
    ) {
        self.activationPolicy = activationPolicy
        self.opensSettingsWindowOnLaunch = opensSettingsWindowOnLaunch
        self.reopensSettingsWindowFromDock = reopensSettingsWindowFromDock
        self.keepsStatusMenu = keepsStatusMenu
        self.bundleLSUIElement = bundleLSUIElement
    }
}

public enum GUIAppLaunchPresenter {
    public static let regularGUIApp = GUIAppLaunchPresentation(
        activationPolicy: "regular",
        opensSettingsWindowOnLaunch: true,
        reopensSettingsWindowFromDock: true,
        keepsStatusMenu: true,
        bundleLSUIElement: false
    )
}
