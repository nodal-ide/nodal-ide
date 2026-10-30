@testable import CodeEdit
import Foundation
import Testing

@MainActor
@Suite
struct XdebugDetectorTests {
    @Test
    func parsePhpInfoExtractsCorrectValue() {
        let sampleInfo = """
        xdebug

        xdebug support => enabled
        xdebug.mode => develop,debug => develop,debug
        xdebug.client_port => 9003 => 9003
        xdebug.start_with_request => yes => yes
        """

        #expect(XdebugDetector.value(of: "xdebug.mode", in: sampleInfo) == "develop,debug")
        #expect(XdebugDetector.value(of: "xdebug.client_port", in: sampleInfo) == "9003")
        #expect(XdebugDetector.value(of: "nonexistent", in: sampleInfo) == nil)
    }

    @Test
    func statusEqualityCoversLoadedVariants() {
        let statusA = XdebugDetector.Status.loaded(
            php: "/usr/local/bin/php",
            version: "3.3.0",
            mode: "debug",
            workspaceName: "MyProject"
        )
        let statusB = XdebugDetector.Status.loaded(
            php: "/usr/local/bin/php",
            version: "3.3.0",
            mode: "debug",
            workspaceName: "MyProject"
        )
        let statusC = XdebugDetector.Status.loaded(
            php: "/usr/local/bin/php",
            version: "3.3.0",
            mode: "debug",
            workspaceName: nil
        )

        #expect(statusA == statusB)
        #expect(statusA != statusC)
        #expect(XdebugDetector.Status.noPHP == XdebugDetector.Status.noPHP)
        #expect(XdebugDetector.Status.checking == XdebugDetector.Status.checking)
    }
}
