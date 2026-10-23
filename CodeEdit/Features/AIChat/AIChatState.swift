import Foundation
import SwiftUI

public enum AIChatMessageRole {
    case user
    case assistant
    case system
}

public struct AIChatMessage: Identifiable, Equatable {
    public let id: UUID
    public let role: AIChatMessageRole
    public let content: String
    public let timestamp: Date
    public let language: String? // For code blocks
    
    public init(id: UUID = UUID(), role: AIChatMessageRole, content: String, timestamp: Date = Date(), language: String? = nil) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.language = language
    }
}

public class AIChatState: ObservableObject {
    @Published public var messages: [AIChatMessage] = []
    @Published public var currentInput: String = ""
    @Published public var isSending: Bool = false
    
    public init() {}
    
    public func sendMessage(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        let userMessage = AIChatMessage(role: .user, content: text)
        messages.append(userMessage)
        currentInput = ""
        
        // For now, we just simulate a response until Phase 2 API is implemented
        isSending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.isSending = false
            let assistantMessage = AIChatMessage(role: .assistant, content: "This is a simulated response. API integration coming in Phase 2.")
            self.messages.append(assistantMessage)
        }
    }
    
    public func clearChat() {
        messages.removeAll()
    }
}
