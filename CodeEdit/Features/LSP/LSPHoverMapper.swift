import Foundation
import CodeEditSourceEditor
import LanguageServerProtocol

enum LSPHoverMapper {
    static func content(
        _ contents: ThreeTypeOption<MarkedString, [MarkedString], MarkupContent>
    ) -> HoverContent? {
        switch contents {
        case .optionA(let marked):
            return content(for: marked)
        case .optionB(let marked):
            return content(for: marked)
        case .optionC(let markup):
            return content(for: markup)
        }
    }

    static func content(for markup: MarkupContent) -> HoverContent? {
        let content: HoverContent
        switch markup.kind {
        case .markdown:
            content = .markdown(markup.value)
        case .plaintext:
            content = .plainText(markup.value)
        }
        return content.isEmpty ? nil : content
    }

    static func content(for marked: MarkedString) -> HoverContent? {
        switch marked {
        case .optionA(let value):
            let content = HoverContent.markdown(value)
            return content.isEmpty ? nil : content
        case .optionB(let pair):
            return content(for: [.optionB(pair)])
        }
    }

    static func content(for marked: [MarkedString]) -> HoverContent? {
        let blocks = marked.compactMap { item -> HoverBlock? in
            switch item {
            case .optionA(let value):
                guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return nil
                }
                return .markdown(value)
            case .optionB(let pair):
                guard !pair.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return nil
                }
                return .code(HoverCode(text: pair.value, language: pair.language.rawValue))
            }
        }
        guard !blocks.isEmpty else { return nil }
        return .document(HoverDocument(blocks: blocks))
    }
}
