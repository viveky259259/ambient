import Foundation

/// What a session waiting on the user needs from them, as one line: approve a command, review a change, answer a
/// question. It's the `reason` of `EventKind.needsInput` and `Activity.waiting`. Remote machines, custom agents and
/// sessions saved by older versions say only `permission` or `question`, which read as `.permission` and `.question`.
public enum Need: String, CaseIterable, Sendable {
    /// Run a shell command.
    case command
    /// Change files: an edit, a new file, a patch.
    case edit
    /// Fetch a page or search the web.
    case web
    /// Reach files or folders outside the project.
    case access
    /// Leave plan mode and act on a plan.
    case plan
    /// Answer a question or fill in a form.
    case question
    /// Use any other tool, or a permission prompt that says no more.
    case permission

    /// The need a stored reason names. Anything unknown is a question: something the agent wants from the user.
    public init(reason: String) {
        self = Need(rawValue: reason) ?? .question
    }

    /// Whether the agent asks to be allowed to do something, which Allow and Deny can answer.
    public var isPermission: Bool { self != .question }

    /// What the user has to do, for the island, the menu and notifications.
    public var headline: String {
        switch self {
        case .command: "Approve a command"
        case .edit: "Review a change"
        case .web: "Allow web access"
        case .access: "Allow access outside the project"
        case .plan: "Review a plan"
        case .question: "Answer a question"
        case .permission: "Approve a tool"
        }
    }

    /// `headline` without its article, for tight spaces.
    public var short: String {
        switch self {
        case .command: "Approve command"
        case .edit: "Review change"
        case .web: "Allow web access"
        case .access: "Allow access"
        case .plan: "Review plan"
        case .question: "Answer question"
        case .permission: "Approve tool"
        }
    }

    /// The need behind a prompt about a tool, as the agent names it.
    public static func forTool(_ name: String) -> Need {
        switch ToolNames.display(name) {
        case "Shell", "Bash": .command
        // "Update" is what Claude's notifications call an edit.
        case "Edit", "Write", "MultiEdit", "NotebookEdit", "Patch", "Update": .edit
        case "Fetch", "Search", "WebFetch", "WebSearch", "Web Search": .web
        case "ExitPlanMode", "exit_plan_mode", "plan_exit": .plan
        case "AskUserQuestion", "Question", "ask_user": .question
        default: .permission
        }
    }

    /// A permission prompt known only by its text: Claude's "Claude needs your permission to use Bash", or a bare tool
    /// name. The tool decides the need, and the rest of the text says nothing the headline doesn't. Other text is the
    /// detail as it is.
    static func fromText(_ text: String?) -> (need: Need, detail: String?) {
        guard let text = Trim.clean(text, max: Limits.message) else { return (.permission, nil) }
        let tool: String? = if let r = text.range(of: "permission to use ", options: .caseInsensitive) {
            text[r.upperBound...].trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: ".?!")))
        } else if text.rangeOfCharacter(from: .whitespaces) == nil {
            text
        } else {
            nil
        }
        guard let tool, !tool.isEmpty else { return (.permission, text) }
        let need = forTool(tool)
        return (need, need == .permission ? ToolNames.display(tool) : nil)
    }
}
