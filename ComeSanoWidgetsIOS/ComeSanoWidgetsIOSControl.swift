//
//  ComeSanoWidgetsIOSControl.swift
//  ComeSanoWidgetsIOS
//
//  Created by Rodrigo Castro Camacho on 02/03/26.
//

import AppIntents
import SwiftUI
import WidgetKit

@available(iOSApplicationExtension 18.0, *)
struct ComeSanoWidgetsIOSControl: ControlWidget {
    static let kind: String = "rcTools.ComeSano.ComeSanoWidgetsIOS"

    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(
            kind: Self.kind,
            provider: Provider()
        ) { value in
            ControlWidgetToggle(
                "Start Timer",
                isOn: value.isRunning,
                action: StartTimerIntent(value.name)
            ) { isRunning in
                Label(isRunning ? "On" : "Off", systemImage: "timer")
            }
        }
        .displayName("Timer")
        .description("A an example control that runs a timer.")
    }
}

extension ComeSanoWidgetsIOSControl {
    @available(iOSApplicationExtension 18.0, *)
    struct Value {
        var isRunning: Bool
        var name: String
    }

    @available(iOSApplicationExtension 18.0, *)
    struct Provider: AppIntentControlValueProvider {
        func previewValue(configuration: TimerConfiguration) -> Value {
            ComeSanoWidgetsIOSControl.Value(isRunning: false, name: configuration.timerName)
        }

        func currentValue(configuration: TimerConfiguration) async throws -> Value {
            let isRunning = true // Check if the timer is running
            return ComeSanoWidgetsIOSControl.Value(isRunning: isRunning, name: configuration.timerName)
        }
    }
}

@available(iOSApplicationExtension 18.0, *)
struct TimerConfiguration: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "Timer Name Configuration"

    @Parameter(title: "Timer Name", default: "Timer")
    var timerName: String
}

@available(iOSApplicationExtension 18.0, *)
struct StartTimerIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Start a timer"

    @Parameter(title: "Timer Name")
    var name: String

    @Parameter(title: "Timer is running")
    var value: Bool

    init() {}

    init(_ name: String) {
        self.name = name
    }

    @available(iOSApplicationExtension 18.0, *)
    func perform() async throws -> some IntentResult {
        // Start the timer…
        return .result()
    }
}
