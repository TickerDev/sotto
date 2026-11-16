import SottoTools

/// A model-selected pause in the turn, rather than a successful native action.
struct ClarificationTool: Tool {
    let descriptor = ToolDescriptor(
        id: "ask_user",
        description: "Ask one short question only when information necessary to carry out the request is missing or ambiguous. This pauses execution until the user replies. Do not use to reconfirm a clear request.",
        properties: ["question": textProperty("One concise question for the user")],
        required: ["question"], risk: .read, capabilities: []
    )
    func execute(arguments: JSONValue) async throws -> ToolResult {
        guard let question = arguments.object?["question"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !question.isEmpty else {
            throw ToolError.invalid("A clarification must contain a question")
        }
        return ToolResult("Waiting for the user's answer", data: .string(question))
    }
}
