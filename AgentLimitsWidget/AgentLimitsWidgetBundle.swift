import WidgetKit
import SwiftUI

@main
struct AgentLimitsWidgetBundle: WidgetBundle {
    var body: some Widget {
        // Usage Limit Widgets
        CodexUsageLimitWidget()
        ClaudeUsageLimitWidget()
        CopilotUsageLimitWidget()
        CustomUsageWidget()
        // Token Usage Widgets
        ClaudeTokenUsageWidget()
        CodexTokenUsageWidget()
        CopilotTokenUsageWidget()
    }
}
