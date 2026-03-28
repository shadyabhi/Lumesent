import Foundation

enum PushoverClient {
    private static let endpoint = URL(string: "https://api.pushover.net/1/messages.json")!

    /// Sends a notification via Pushover. Call from any queue; completion is invoked on a background URLSession queue.
    static func send(appToken: String, userKey: String, title: String, message: String, completion: @escaping (Result<Void, Error>) -> Void) {
        AppLog.shared.debug("pushover: URLSession POST \(endpoint.host ?? "api.pushover.net", privacy: .public)")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        let body = formEncoded([
            ("token", appToken),
            ("user", userKey),
            ("title", title),
            ("message", message),
        ])
        request.httpBody = body.data(using: .utf8)

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                AppLog.shared.error("pushover: transport error \(error.localizedDescription, privacy: .public)")
                completion(.failure(error))
                return
            }
            guard let http = response as? HTTPURLResponse else {
                AppLog.shared.error("pushover: response not HTTP")
                completion(.failure(NSError(domain: "PushoverClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])))
                return
            }
            if (200...299).contains(http.statusCode) {
                AppLog.shared.debug("pushover: HTTP \(http.statusCode, privacy: .public) OK bytes=\(data?.count ?? 0, privacy: .public)")
                completion(.success(()))
                return
            }
            let snippet = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let clipped = snippet.count > 400 ? String(snippet.prefix(400)) + "…" : snippet
            AppLog.shared.error("pushover: HTTP \(http.statusCode, privacy: .public) body=\(clipped, privacy: .public)")
            completion(.failure(NSError(domain: "PushoverClient", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: snippet])))
        }
        task.resume()
    }

    private static func formEncoded(_ pairs: [(String, String)]) -> String {
        pairs.map { key, value in
            "\(formEncode(key))=\(formEncode(value))"
        }.joined(separator: "&")
    }

    private static func formEncode(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~ ")
        return s.addingPercentEncoding(withAllowedCharacters: allowed)?.replacingOccurrences(of: " ", with: "+") ?? s
    }
}
