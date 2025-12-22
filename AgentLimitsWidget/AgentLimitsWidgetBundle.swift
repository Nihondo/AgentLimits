import WidgetKit
import SwiftUI

@main
struct AgentLimitsWidgetBundle: WidgetBundle {
    var body: some Widget {
        CodexUsageLimitWidget()
        ClaudeUsageLimitWidget()
    }
}
