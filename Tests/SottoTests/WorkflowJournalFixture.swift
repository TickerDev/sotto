import Foundation
import XCTest
@testable import SottoIntegrations

extension XCTestCase {
    func temporaryWorkflowJournal() -> WorkflowJournal {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SottoRecoveryTests-" + UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return WorkflowJournal(directory: directory)
    }
}
