import Foundation

// Spotify ships a number of finished-but-unreleased features behind its own
// remote-config flags. Each group here forces one such feature on through the
// bootstrap patch (same channel as the Liquid Glass flags). Flag identifiers
// are Spotify's own; the grouping and implementation are original.
struct SPModLabGroup: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let flags: [String]
}

enum SPModLabs {
    static let groups: [SPModLabGroup] = [
        SPModLabGroup(
            id: "ai_chat",
            title: "labs_ai_chat",
            subtitle: "labs_ai_chat_subtitle",
            flags: [
                "ios-home-evopage-impl.interactive_entrypoint_enabled",
                "ios-home-evopage-impl.interactive_entrypoint_martini_enabled",
                "ios-home-evopage-impl.interactive_entrypoint_floating_chat_enabled",
                "ios-home-evopage-impl.interactive_entrypoint_mic_enabled",
                "ios-home-evopage-impl.interactive_entrypoint_pill_glow_enabled",
                "ios-martini-floatingchat-impl.intent_pills_enabled",
                "ios-martini-floatingchat-impl.thinking_states_enabled",
                "ios-martini-floatingchat-impl.voice_recording_enabled",
                "ios-martini-npvcardprovider-impl.floating_chat_entry_point_enabled"
            ]
        ),
        SPModLabGroup(
            id: "comments",
            title: "labs_comments",
            subtitle: "labs_comments_subtitle",
            flags: [
                "ios-feature-comments.enable_comments_card",
                "ios-feature-comments.enable_pinned_comments",
                "ios-feature-comments.enable_multi_reactions"
            ]
        ),
        SPModLabGroup(
            id: "local_files",
            title: "labs_local_files",
            subtitle: "labs_local_files_subtitle",
            flags: [
                "ios-feature-localfiles.documents_enabled"
            ]
        ),
        SPModLabGroup(
            id: "sleep_timer",
            title: "labs_sleep_timer",
            subtitle: "labs_sleep_timer_subtitle",
            flags: [
                "ios-feature-sleeptimer.enable_fade_out",
                "ios-feature-sleeptimer.enable_one_minute_option",
                "ios-feature-sleeptimer.use_options_sheet"
            ]
        ),
        SPModLabGroup(
            id: "widget_progress",
            title: "labs_widget_progress",
            subtitle: "labs_widget_progress_subtitle",
            flags: [
                "ios-widgets-widgetremoteconfig-impl.progress_bar_enabled"
            ]
        ),
        SPModLabGroup(
            id: "cover_snake",
            title: "labs_cover_snake",
            subtitle: "labs_cover_snake_subtitle",
            flags: [
                "ios-feature-cover-art-snake.enabled"
            ]
        )
    ]

    // Every flag name that any currently-enabled group turns on.
    static var enabledFlags: [String] {
        let enabled = UserDefaults.enabledLabGroups
        return groups
            .filter { enabled.contains($0.id) }
            .flatMap { $0.flags }
    }
}

extension UserDefaults {
    static let enabledLabGroupsKey = "enabledLabGroups"

    static var enabledLabGroups: Set<String> {
        get {
            let array = container.array(forKey: enabledLabGroupsKey) as? [String] ?? []
            return Set(array)
        }
        set {
            container.set(Array(newValue), forKey: enabledLabGroupsKey)
        }
    }
}
