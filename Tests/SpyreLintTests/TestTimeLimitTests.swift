import Foundation
import Testing

/// Every test file must declare a suite with a time limit, so a hang fails fast.
@Suite(.timeLimit(.minutes(1)))
struct TestTimeLimitTests {
    @Test func everyTestFileHasATimeLimit() throws {
        let tests = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let folders = try FileManager.default.contentsOfDirectory(at: tests, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasSuffix("Tests") }
        #expect(!folders.isEmpty)
        for folder in folders {
            let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "swift" }
            for file in files {
                let source = try String(contentsOf: file, encoding: .utf8)
                #expect(
                    source.contains("@Suite(.timeLimit("),
                    "\(folder.lastPathComponent)/\(file.lastPathComponent) has no suite time limit"
                )
            }
        }
    }
}
