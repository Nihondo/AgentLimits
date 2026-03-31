import WidgetKit
import SwiftUI

@main
struct AgentLimitsWidgetBundle: WidgetBundle {
    var body: some Widget {
        // Usage Limit Widgets
        CodexUsageLimitWidget()
        ClaudeUsageLimitWidget()
        CopilotUsageLimitWidget()
        // Token Usage Widgets
        ClaudeTokenUsageWidget()
        CodexTokenUsageWidget()
        CopilotTokenUsageWidget()
    }
}
