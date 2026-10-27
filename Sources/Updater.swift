import Foundation
import SwiftUI

private let v2aRepository = "Molank/v2a"

/// 用 GitHub Releases 做「检查更新」：只比较版本号并跳转下载页，不做自动替换
@MainActor
final class UpdateChecker: ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String, url: URL)
        case failed(String)
    }

    @Published var state: State = .idle

    var currentVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
    }

    func check() {
        guard state != .checking else { return }
        state = .checking

        guard let endpoint = URL(string: "https://api.github.com/repos/\(v2aRepository)/releases/latest") else {
            state = .failed("链接无效")
            return
        }
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("V2A/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { data, response, error in
            let result = Self.parse(data: data, response: response, error: error,
                                    current: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0")
            // 未登录的 API 每小时只有 60 次，超限时退回读 releases/latest 的跳转地址
            if case .failed = result {
                Self.checkViaRedirect(current: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0") { fallback in
                    DispatchQueue.main.async {
                        self.state = (fallback ?? result)
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.state = result
                }
            }
        }.resume()
    }

    // MARK: - 兜底：读 releases/latest 的 302 目标

    private final class RedirectCatcher: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        var target: URL?
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) {
            target = request.url
            completionHandler(nil)
        }
    }

    nonisolated private static func checkViaRedirect(current: String,
                                                     completion: @escaping (State?) -> Void) {
        guard let url = URL(string: "https://github.com/\(v2aRepository)/releases/latest") else {
            completion(nil)
            return
        }
        let catcher = RedirectCatcher()
        let session = URLSession(configuration: .ephemeral, delegate: catcher, delegateQueue: nil)
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("V2A/\(current)", forHTTPHeaderField: "User-Agent")
        session.dataTask(with: request) { _, _, _ in
            defer { session.finishTasksAndInvalidate() }
            guard let target = catcher.target,
                  let tag = target.pathComponents.last(where: { $0.hasPrefix("v") }) else {
                completion(nil)
                return
            }
            let version = String(tag.dropFirst())
            if compare(version, current) > 0 {
                completion(.available(version: version, url: target))
            } else {
                completion(.upToDate)
            }
        }.resume()
    }

    // MARK: - 解析

    nonisolated private static func parse(data: Data?, response: URLResponse?, error: Error?,
                                          current: String) -> State {
        if let error {
            return .failed(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            return .failed("没有收到响应")
        }
        if http.statusCode == 403 {
            return .failed("请求太频繁，稍后再试")
        }
        guard http.statusCode == 200, let data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failed("服务器返回 \(http.statusCode)")
        }

        let tag = (json["tag_name"] as? String) ?? ""
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let page = (json["html_url"] as? String) ?? "https://github.com/\(v2aRepository)/releases"
        let url = URL(string: page) ?? URL(string: "https://github.com")!

        guard !version.isEmpty else { return .failed("没有解析到版本号") }
        if compare(version, current) > 0 {
            return .available(version: version, url: url)
        }
        return .upToDate
    }

    nonisolated static func compare(_ lhs: String, _ rhs: String) -> Int {
        let a = lhs.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
        let b = rhs.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            if x != y { return x > y ? 1 : -1 }
        }
        return 0
    }
}
