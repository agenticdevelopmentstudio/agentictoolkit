//
//  UserSettings+SessionWatcher.swift
//  AgenticToolkit
//
//  Created by Mike Fullerton on 4/29/26.
//

import AgenticToolkitCore

extension UserSettings {

    /// Raw value of the configured `SessionWatcherClickAction` for session list clicks.
    public static var clickAction = UserSetting<String>(
        "click_action",
        default: SessionWatcher.SessionWatcherClickAction.defaultAction.rawValue
    )

    /// Custom command template (shell expression) used by the custom-command click action.
    public static var customCommandTemplate = UserSetting<String>("custom_command_template", default: "")

    /// Seconds of inactivity before a session is marked stale by the liveness monitor.
    public static var stalenessTimeout = UserSetting<Double>("staleness_timeout", default: 300.0)

    /// Whether the session panel floats above all other windows.
    static public var alwaysOnTop = UserSetting<Bool>("always_on_top", default: true)
}

extension UserSettings {

    // `sessionWindowAlwaysOnTop` and `sessionWindowTransparency` are declared
    // in `WindowController.swift` — reused here.
    // `aiSummariesEnabled` is declared in `AIModelChatConfig.swift` — reused.

    /// Seconds of inactivity before a session is marked stale.
    static var sessionStalenessTimeout = UserSetting<Double>(
        "session_staleness_timeout",
        default: 120
    )

    /// Raw value of `SessionWatcherClickAction` for the click action.
    static var sessionClickAction = UserSetting<String>(
        "session_click_action",
        default: SessionWatcher.SessionWatcherClickAction.openTerminal.rawValue
    )

    /// Shell command template used when click action is `customCommand`.
    static var sessionCustomCommand = UserSetting<String>(
        "session_custom_command",
        default: ""
    )
}

extension UserSettings {

    /// Whether to post a notification when a Claude Code session starts.
    public static var notifySessionStart = UserSetting<Bool>("notify_session_start", default: false)

    /// Whether to post a notification when a Claude Code session ends.
    public static var notifySessionEnd = UserSetting<Bool>("notify_session_end", default: false)

    /// Whether to post a notification when a session goes stale.
    public static var notifyStale = UserSetting<Bool>("notify_stale", default: false)
}
