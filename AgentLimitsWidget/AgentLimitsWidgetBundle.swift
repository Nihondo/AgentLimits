import WidgetKit
import SwiftUI

@main
struct AgentLimitsWidgetBundle: WidgetBundle {
    var body: some Widget {
        // Usage Limit Widgets
        CodexUsageLimitWidget()
        ClaudeUsageLimitWidget()
        // Token Usage Widgets (ccusage)
        ClaudeTokenUsageWidget()
        CodexTokenUsageWidget()
    }
}
