import Foundation
import UIKit

func modifyRemoteConfiguration(_ configuration: inout UcsResponse) {
    modifyAttributes(&configuration.attributes.accountAttributes)

    if UserDefaults.overwriteConfiguration,
       let resolveConfiguration = try? BundleHelper.shared.resolveConfiguration() {
        configuration.resolve.configuration = resolveConfiguration
    }
    else {
        modifyAssignedValues(&configuration.assignedValues)
    }

    if UserDefaults.playerLiquidGlass {
        forceLiquidGlassFlags(&configuration.assignedValues)
    }
}

// Spotify ships its iOS 26 Liquid Glass surfaces behind remote-config flags that
// default off. Forcing them on turns on the glass navigation bar, the new player
// slider, the sheet-style player, the bottom-sheet queue and Connect panels, the
// redesigned player header and the sleep-timer options sheet.
private let liquidGlassFlags: [(scope: String, name: String)] = [
    ("ios-reprise-liquid-glass-properties", "context_menu_in_navigation_bar_enabled"),
    ("ios-feature-encoreexperiments", "new_npv_slider_enabled"),
    ("ios-feature-nowplaying", "sheet_style_npv"),
    ("ios-feature-nowplaying", "bottom_sheet_queue_enabled"),
    ("ios-feature-nowplaying", "new_redesign_header_with_context_menu_enabled"),
    ("ios-feature-nowplaying-elements", "enable_connect_bottom_sheet"),
    ("ios-playbackcontrol-audiovideoswitcher-impl", "enable_connect_bottom_sheet"),
    ("ios-feature-sleeptimer", "use_options_sheet")
]

private func forceLiquidGlassFlags(_ values: inout [AssignedValue]) {
    for flag in liquidGlassFlags {
        let enabled = BoolValue.with { $0.value = true }

        if let index = values.firstIndex(where: {
            $0.propertyID.scope == flag.scope && $0.propertyID.name == flag.name
        }) {
            values[index].boolValue = enabled
        }
        else {
            values.append(AssignedValue.with {
                $0.propertyID = AssignedIdentifier.with {
                    $0.scope = flag.scope
                    $0.name = flag.name
                }
                $0.boolValue = enabled
            })
        }
    }
}

private let propertyReplacements = [
    // capping
    EeveePropertyReplacement(name: "enable_common_capping", modification: .remove),
    EeveePropertyReplacement(name: "enable_pns_common_capping", modification: .remove),
    EeveePropertyReplacement(name: "enable_pick_and_shuffle_common_capping", modification: .remove),
    EeveePropertyReplacement(name: "enable_pick_and_shuffle_dynamic_cap", modification: .remove),
    EeveePropertyReplacement(name: "pick_and_shuffle_timecap", modification: .remove),
    EeveePropertyReplacement(scope: "ios-feature-queue", modification: .remove),
    
    // also capping idk
    EeveePropertyReplacement(name: "enable_free_on_demand_experiment", modification: .remove),
    EeveePropertyReplacement(name: "enable_free_on_demand_context_menu_experiment", modification: .remove),
    EeveePropertyReplacement(name: "enable_mft_plus_queue", modification: .remove),
    EeveePropertyReplacement(name: "enable_mft_plus_extended_queue", modification: .remove),
    EeveePropertyReplacement(name: "enable_playback_timeout_service", modification: .setBool(false)),
    EeveePropertyReplacement(name: "enable_playback_timeout_error_ui", modification: .setBool(false)),
    EeveePropertyReplacement(name: "playback_timeout_action", modification: .setEnum("Nothing")),
    EeveePropertyReplacement(name: "is_remove_from_queue_enabled_for_mft_plus", modification: .remove),
    EeveePropertyReplacement(name: "is_reordering_for_mft_plus_allowed", modification: .remove),
    
    // 😡😡😡 spotify, stop changing the scroll logic
    EeveePropertyReplacement(name: "should_nova_scroll_use_scrollsita", modification: .remove)
]

private func modifyAssignedValues(_ values: inout [AssignedValue]) {
    for replacement in propertyReplacements {
        let matchingIndices = values.indices.filter({ index in
            let value = values[index]
            let nameMatches = replacement.name.map { value.propertyID.name == $0 } ?? true
            let scopeMatches = replacement.scope.map { value.propertyID.scope == $0 } ?? true
            return nameMatches && scopeMatches
        })
        
        for index in matchingIndices.sorted(by: >) {
            switch replacement.modification {
            case .remove:
                values.remove(at: index)
                
            case .setBool(let newValue):
                values[index].boolValue = BoolValue.with { $0.value = newValue }
                
            case .setEnum(let newValue):
                values[index].enumValue = EnumValue.with { $0.value = newValue }
            }
        }
    }
}

private func modifyAttributes(_ attributes: inout [String: AccountAttribute]) {
    let oneYearFromNow = (Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date().addingTimeInterval(31_536_000))
    
    let formatter = ISO8601DateFormatter()
    formatter.timeZone = TimeZone(abbreviation: "UTC")
    
    attributes["ads"] = AccountAttribute.with {
        $0.boolValue = false
    }

    attributes["can_use_superbird"] = AccountAttribute.with {
        $0.boolValue = true
    }

    attributes["catalogue"] = AccountAttribute.with {
        $0.stringValue = "premium"
    }

    attributes["financial-product"] = AccountAttribute.with {
        $0.stringValue = "pr:premium,tc:0"
    }

    attributes["is-eligible-premium-unboxing"] = AccountAttribute.with {
        $0.boolValue = true
    }

    attributes["name"] = AccountAttribute.with {
        $0.stringValue = "Spotify Premium"
    }

    attributes["nft-disabled"] = AccountAttribute.with {
        $0.stringValue = "1"
    }

    attributes["offline"] = AccountAttribute.with {
        $0.boolValue = true // allow downloading
    }

    attributes["on-demand"] = AccountAttribute.with {
        $0.boolValue = true
    }

    attributes["payments-initial-campaign"] = AccountAttribute.with {
        $0.stringValue = "default"
    }

    attributes["player-license"] = AccountAttribute.with {
        $0.stringValue = "premium"
    }

    attributes["player-license-v2"] = AccountAttribute.with {
        $0.stringValue = "premium"
    }

    attributes["product-expiry"] = AccountAttribute.with {
        $0.stringValue = formatter.string(from: oneYearFromNow)
    }

    attributes["shuffle-eligible"] = AccountAttribute.with {
        $0.boolValue = true
    }

    attributes["social-session"] = AccountAttribute.with {
        $0.boolValue = true
    }

    attributes["social-session-free-tier"] = AccountAttribute.with {
        $0.boolValue = false
    }

    attributes["streaming-rules"] = AccountAttribute.with {
        $0.stringValue = ""
    }

    attributes["subscription-enddate"] = AccountAttribute.with {
        $0.stringValue = formatter.string(from: oneYearFromNow)
    }

    attributes["type"] = AccountAttribute.with {
        $0.stringValue = "premium"
    }

    attributes["unrestricted"] = AccountAttribute.with {
        $0.boolValue = true
    }

    attributes.removeValue(forKey: "payment-state")
    attributes.removeValue(forKey: "last-premium-activation-date")
}
