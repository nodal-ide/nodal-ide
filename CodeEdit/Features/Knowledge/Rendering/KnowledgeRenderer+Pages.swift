import Foundation

extension KnowledgeRenderer {
    static func isHTMLPage(_ path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        return ext == "html" || ext == "htm"
    }
}
