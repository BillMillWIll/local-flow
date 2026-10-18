import Foundation
import Testing
@testable import LocalFlowCore

@Test func drainsLargeStandardErrorWithoutBlocking() throws {
    let result = try LocalProcess.run(URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "/usr/bin/head -c 1000000 /dev/zero >&2"])
    #expect(result.status == 0)
    #expect(result.standardError.utf8.count == 1_000_000)
}

@Test func discardsUnusedStandardOutputWithoutBlocking() throws {
    let result = try LocalProcess.run(URL(fileURLWithPath: "/usr/bin/head"), arguments: ["-c", "1000000", "/dev/zero"])
    #expect(result.status == 0)
    #expect(result.standardError.isEmpty)
}

@Test func retainsFailureStatusAndDiagnostic() throws {
    let result = try LocalProcess.run(URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "printf 'Diagnose' >&2; exit 7"])
    #expect(result.status == 7)
    #expect(result.standardError == "Diagnose")
}
