import Foundation

@MainActor
protocol AssistantRetrievalProviding: AnyObject {
    var status: AssistantRetrievalStatus { get }
    func setStatusHandler(_ handler: ((AssistantRetrievalStatus) -> Void)?)
    func start()
    func stop()
    func rebuild()
    func clear()
    func retrieve(_ query: AssistantRetrievalQuery) async -> AssistantRetrievalResult
}
