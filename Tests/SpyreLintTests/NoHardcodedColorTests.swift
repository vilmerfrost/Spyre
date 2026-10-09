import Foundation
import Testing

@Suite(.timeLimit(.minutes(1)))
struct NoHardcodedColorTests {
    /// `AGENTS.md`: views use design tokens only. A hardcoded color in a view is a bug.
    /// This test scans every file in `Sources/Spyre/Views`.
    @Test func viewsContainNoHardcodedColors() throws {
        let views = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Spyre/Views")
        let files = try FileManager.default.contentsOfDirectory(at: views, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        #expect(!files.isEmpty)

        let named = "black|white|gray|red|orange|yellow|green|mint|teal|cyan|blue|indigo|purple|pink|brown|primary|secondary"
        let patterns = [
            #"\bColor\s*[.(]"#,
            #"\b(NS|UI)Color\b"#,
            #"#colorLiteral"#,
            #"\.(foregroundStyle|foregroundColor|background|tint|fill|stroke)\(\s*\.(\#(named))\b"#,
        ]
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            for pattern in patterns {
                let found = source.range(of: pattern, options: .regularExpression)
                #expect(found == nil, "\(file.lastPathComponent) matches \(pattern)")
            }
        }
    }
}
