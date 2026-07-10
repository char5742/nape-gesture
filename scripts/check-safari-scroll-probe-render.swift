import Foundation
import WebKit

private struct ProbeCheckError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

private final class FixtureSchemeHandler: NSObject, WKURLSchemeHandler {
    private let fixtureRoot: URL

    init(fixtureRoot: URL) {
        self.fixtureRoot = fixtureRoot.standardizedFileURL
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let requestURL = urlSchemeTask.request.url,
              requestURL.host == "fixture"
        else {
            urlSchemeTask.didFailWithError(ProbeCheckError(message: "fixture URL が不正です。"))
            return
        }

        let relativePath = requestURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let fileURL = fixtureRoot.appendingPathComponent(relativePath).standardizedFileURL
        guard fileURL.deletingLastPathComponent() == fixtureRoot,
              let data = try? Data(contentsOf: fileURL)
        else {
            urlSchemeTask.didFailWithError(
                ProbeCheckError(message: "fixture を読み取れません: \(relativePath)")
            )
            return
        }

        let response = URLResponse(
            url: requestURL,
            mimeType: "text/html",
            expectedContentLength: data.count,
            textEncodingName: "utf-8"
        )
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}

private final class NavigationObserver: NSObject, WKNavigationDelegate {
    var didFinish = false
    var failure: Error?

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        didFinish = true
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        failure = error
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        failure = error
    }
}

private func waitUntil(
    timeout: TimeInterval = 10,
    condition: () throws -> Bool
) throws {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        if try condition() {
            return
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
    } while Date() < deadline
    throw ProbeCheckError(message: "WebKit fixture の待機がtimeoutしました。")
}

private func evaluate(_ script: String, in webView: WKWebView) throws -> Any {
    var completed = false
    var result: Any?
    var failure: Error?
    webView.evaluateJavaScript(script) { value, error in
        result = value
        failure = error
        completed = true
    }
    try waitUntil { completed }
    if let failure {
        throw failure
    }
    guard let result else {
        throw ProbeCheckError(message: "JavaScript評価が値を返しませんでした。")
    }
    return result
}

private func evaluateJSON(_ script: String, in webView: WKWebView) throws -> [String: Any] {
    guard let json = try evaluate("JSON.stringify(\(script))", in: webView) as? String,
          let data = json.data(using: .utf8),
          let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
        throw ProbeCheckError(message: "probe snapshot をJSON objectとして取得できませんでした。")
    }
    return object
}

private func dictionary(_ value: Any?, path: String) throws -> [String: Any] {
    guard let value = value as? [String: Any] else {
        throw ProbeCheckError(message: "\(path) がobjectではありません。")
    }
    return value
}

private func integer(_ value: Any?, path: String) throws -> Int {
    guard let number = value as? NSNumber,
          CFGetTypeID(number) != CFBooleanGetTypeID(),
          Double(number.intValue) == number.doubleValue
    else {
        throw ProbeCheckError(message: "\(path) がintegerではありません。")
    }
    return number.intValue
}

private func boolean(_ value: Any?, path: String) throws -> Bool {
    guard let number = value as? NSNumber,
          CFGetTypeID(number) == CFBooleanGetTypeID()
    else {
        throw ProbeCheckError(message: "\(path) がbooleanではありません。")
    }
    return number.boolValue
}

private func expectedMaximumY(contractURL: URL) throws -> Int {
    let data = try Data(contentsOf: contractURL)
    guard let contract = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let fixtures = contract["fixtures"] as? [[String: Any]]
    else {
        throw ProbeCheckError(message: "contract fixtures を読み取れません。")
    }

    var values: [Int] = []
    for fixture in fixtures {
        guard let scenario = fixture["scenario"] as? String,
              scenario == "nested" || scenario == "frame",
              let reset = fixture["resetExpect"] as? [String: Any]
        else {
            continue
        }
        let path = scenario == "nested" ? "frame.maxY" : "scroll.maxY"
        let rule = try dictionary(reset[path], path: "\(scenario).resetExpect.\(path)")
        guard rule["comparison"] as? String == "exact" else {
            throw ProbeCheckError(message: "\(scenario).resetExpect.\(path) はexact比較が必要です。")
        }
        values.append(try integer(rule["value"], path: "\(scenario).resetExpect.\(path).value"))
    }

    guard values.count == 2, values[0] == values[1] else {
        throw ProbeCheckError(message: "nested/frame のmaxY契約値が一致しません。")
    }
    return values[0]
}

private func frameSnapshot(from aggregate: [String: Any], key: String) throws -> [String: Any] {
    let source = try dictionary(aggregate[key], path: key)
    if key == "nested" {
        return try dictionary(source["frame"], path: "nested.frame")
    }
    return try dictionary(source["scroll"], path: "frame.scroll")
}

private func assertInitialState(
    _ aggregate: [String: Any],
    expectedMaxY: Int
) throws {
    for key in ["nested", "frame"] {
        let frame = try frameSnapshot(from: aggregate, key: key)
        let prefix = key == "nested" ? "nested.frame" : "frame.scroll"
        guard try integer(frame["y"], path: "\(prefix).y") == 0,
              try integer(frame["maxY"], path: "\(prefix).maxY") == expectedMaxY,
              try boolean(frame["atEnd"], path: "\(prefix).atEnd") == false
        else {
            throw ProbeCheckError(message: "\(prefix) の初期render値が契約と一致しません。")
        }
    }
}

private func assertEndpointState(
    _ aggregate: [String: Any],
    expectedMaxY: Int
) throws {
    for key in ["nested", "frame"] {
        let frame = try frameSnapshot(from: aggregate, key: key)
        let prefix = key == "nested" ? "nested.frame" : "frame.scroll"
        let y = try integer(frame["y"], path: "\(prefix).y")
        let maxY = try integer(frame["maxY"], path: "\(prefix).maxY")
        let atEnd = try boolean(frame["atEnd"], path: "\(prefix).atEnd")
        guard y == expectedMaxY, maxY == expectedMaxY, atEnd, y >= maxY else {
            throw ProbeCheckError(message: "\(prefix) が実render終端を表していません。")
        }
    }
}

private func parsePaths() throws -> (contract: URL, fixtureRoot: URL) {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    var contract = repositoryRoot.appendingPathComponent("docs/fixtures/safari-scroll-probe/contract.json")
    var fixtureRoot = repositoryRoot.appendingPathComponent("docs/fixtures/safari-scroll-probe")
    var index = 1
    let arguments = CommandLine.arguments
    while index < arguments.count {
        guard index + 1 < arguments.count else {
            throw ProbeCheckError(message: "\(arguments[index]) の値がありません。")
        }
        switch arguments[index] {
        case "--contract":
            contract = URL(fileURLWithPath: arguments[index + 1])
        case "--fixture-root":
            fixtureRoot = URL(fileURLWithPath: arguments[index + 1])
        default:
            throw ProbeCheckError(message: "未知の引数です: \(arguments[index])")
        }
        index += 2
    }
    return (contract.standardizedFileURL, fixtureRoot.standardizedFileURL)
}

do {
    let paths = try parsePaths()
    let expectedMaxY = try expectedMaximumY(contractURL: paths.contract)
    let configuration = WKWebViewConfiguration()
    let schemeHandler = FixtureSchemeHandler(fixtureRoot: paths.fixtureRoot)
    configuration.websiteDataStore = .nonPersistent()
    configuration.setURLSchemeHandler(schemeHandler, forURLScheme: "nape-probe")

    let webView = WKWebView(
        frame: CGRect(x: 0, y: 0, width: 1200, height: 900),
        configuration: configuration
    )
    let observer = NavigationObserver()
    webView.navigationDelegate = observer
    guard let fixtureURL = URL(string: "nape-probe://fixture/nested.html") else {
        throw ProbeCheckError(message: "fixture URLを生成できません。")
    }
    webView.load(URLRequest(url: fixtureURL))
    try waitUntil {
        if let failure = observer.failure {
            throw failure
        }
        return observer.didFinish
    }
    try waitUntil {
        (try evaluate(
            "window.napeGestureScrollProbe?.snapshot?.().ready === true",
            in: webView
        ) as? Bool) == true
    }

    let snapshotScript = """
    ({
      nested: window.napeGestureScrollProbe.snapshot(),
      frame: document.querySelector('#frame').contentWindow.napeGestureScrollProbe.snapshot()
    })
    """
    try assertInitialState(try evaluateJSON(snapshotScript, in: webView), expectedMaxY: expectedMaxY)

    _ = try evaluate(
        "document.querySelector('#frame').contentWindow.scrollTo(0, 1000000); true",
        in: webView
    )
    try waitUntil {
        let aggregate = try evaluateJSON(snapshotScript, in: webView)
        let nested = try frameSnapshot(from: aggregate, key: "nested")
        let frame = try frameSnapshot(from: aggregate, key: "frame")
        return try boolean(nested["atEnd"], path: "nested.frame.atEnd")
            && boolean(frame["atEnd"], path: "frame.scroll.atEnd")
    }
    try assertEndpointState(try evaluateJSON(snapshotScript, in: webView), expectedMaxY: expectedMaxY)

    print("Safari scroll probe のWebKit render契約を確認しました: maxY=\(expectedMaxY)")
} catch {
    fputs("Safari scroll probe のWebKit render契約に失敗しました: \(error.localizedDescription)\n", stderr)
    exit(1)
}
