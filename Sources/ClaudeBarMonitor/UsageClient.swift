import Foundation

/// One usage window as returned by the Claude usage endpoint.
struct UsageWindow: Decodable {
    let utilization: Double      // 0-100, percent already used
    let resetsAt: Date?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.utilization = try c.decode(Double.self, forKey: .utilization)
        if let raw = try? c.decode(String.self, forKey: .resetsAt) {
            self.resetsAt = ISO8601DateFormatter.claude.date(from: raw)
        } else {
            self.resetsAt = nil
        }
    }
}

struct UsageResponse: Decodable {
    let fiveHour: UsageWindow
    let sevenDay: UsageWindow?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }
}

/// The result the UI consumes — either fresh usage or a typed failure.
enum UsageResult {
    case success(UsageResponse)
    case needsLogin            // 401/403 or missing credentials
    case offline               // timeout / no network
    case apiError(String)      // unexpected shape / status
}

/// Fetches Claude usage using locally-decrypted desktop cookies.
struct UsageClient {
    private let decryptor = CookieDecryptor()
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.httpShouldSetCookies = false
        self.session = URLSession(configuration: config)
    }

    func fetch() async -> UsageResult {
        let creds: ClaudeCredentials
        do {
            creds = try decryptor.loadCredentials()
        } catch CookieError.sessionKeyMissing {
            return .needsLogin
        } catch {
            return .apiError(String(describing: error))
        }
        guard !creds.organizationId.isEmpty else { return .needsLogin }

        guard let url = URL(string:
            "https://claude.ai/api/organizations/\(creds.organizationId)/usage") else {
            return .apiError("bad url")
        }
        var req = URLRequest(url: url)
        req.setValue(creds.cookieHeader, forHTTPHeaderField: "Cookie")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("https://claude.ai/", forHTTPHeaderField: "Referer")
        req.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
            forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                return .apiError("no http response")
            }
            switch http.statusCode {
            case 200:
                do {
                    let usage = try JSONDecoder().decode(UsageResponse.self, from: data)
                    return .success(usage)
                } catch {
                    return .apiError("JSON shape changed: \(error)")
                }
            case 401, 403:
                return .needsLogin
            default:
                return .apiError("HTTP \(http.statusCode)")
            }
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain {
                return .offline
            }
            return .apiError(nsError.localizedDescription)
        }
    }
}

extension ISO8601DateFormatter {
    /// Claude returns fractional seconds, e.g. 2026-06-13T17:10:00.661321+00:00
    static let claude: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
