import Foundation
import Testing
@testable import ScholiumApplication

@Suite("Codex process network environment")
struct CodexAppServerEnvironmentTests {
  @Test("The isolated runtime keeps proxy routing but excludes unrelated credentials")
  func preservesRouting() {
    let home = URL(fileURLWithPath: "/fixture/isolated-codex")
    let inherited = ["HTTPS_PROXY": "http://127.0.0.1:8080", "http_proxy": "http://127.0.0.1:8080",
      "NO_PROXY": "localhost,127.0.0.1", "PATH": "/usr/bin", "CODEX_HOME": "/wrong/home",
      "OPENAI_API_KEY": "synthetic-secret", "UNRELATED_TOKEN": "synthetic-secret"]
    let actual = CodexAppServer.processEnvironment(inherited, home: home)
    #expect(actual["HTTPS_PROXY"] == inherited["HTTPS_PROXY"])
    #expect(actual["http_proxy"] == inherited["http_proxy"])
    #expect(actual["NO_PROXY"] == inherited["NO_PROXY"])
    #expect(actual["CODEX_HOME"] == home.path)
    #expect(actual["OPENAI_API_KEY"] == nil && actual["UNRELATED_TOKEN"] == nil)
  }
}
