import Foundation
import AppIntents

enum HBError: LocalizedError, CustomLocalizedStringResourceConvertible {
    case notConfigured, badURL, login, notFound
    case http(Int)
    case unsupported(String)
    case network(String)

    var message: String {
        switch self {
        case .notConfigured: "Set your Homebridge address in the app first."
        case .badURL: "The Homebridge address isn't valid."
        case .login: "Homebridge rejected the username or password."
        case .notFound: "I can't find that device on Homebridge."
        case .http(let code): "Homebridge answered with error \(code)."
        case .unsupported(let name): "\(name) can't do that."
        case .network(let text): "Can't reach Homebridge: \(text)"
        }
    }
    var errorDescription: String? { message }
    var localizedStringResource: LocalizedStringResource { "\(message)" }
}

/// One controllable Homebridge service, flattened to what the UI needs.
struct Accessory: Identifiable, Hashable {
    let id: String
    var name: String
    var kind: String
    var values: [String: Double]
    var writable: Set<String>
    var ranges: [String: ClosedRange<Double>]
    var steps: [String: Double]

    // MARK: Power
    var powerKey: String? {
        if writable.contains("On") { return "On" }
        if writable.contains("Active") { return "Active" }
        return nil
    }
    var isOn: Bool {
        guard let k = powerKey else { return false }
        return (values[k] ?? 0) != 0
    }

    // MARK: Climate
    var modeKey: String? { writable.contains("TargetHeaterCoolerState") ? "TargetHeaterCoolerState" : nil }
    var mode: Int? { modeKey.flatMap { values[$0] }.map { Int($0) } }

    var targetKey: String? {
        if writable.contains("TargetTemperature") { return "TargetTemperature" }
        if mode == 1, writable.contains("HeatingThresholdTemperature") { return "HeatingThresholdTemperature" }
        if writable.contains("CoolingThresholdTemperature") { return "CoolingThresholdTemperature" }
        if writable.contains("HeatingThresholdTemperature") { return "HeatingThresholdTemperature" }
        return nil
    }
    var targetTemp: Double? { targetKey.flatMap { values[$0] } }
    var currentTemp: Double? { values["CurrentTemperature"] }
    var isClimate: Bool { targetKey != nil }

    var symbol: String {
        let k = kind.lowercased()
        if isClimate { return "air.conditioner.horizontal.fill" }
        if k.contains("light") { return "lightbulb.fill" }
        if k.contains("fan") { return "fan.fill" }
        if k.contains("outlet") { return "powerplug.fill" }
        if k.contains("switch") { return "switch.2" }
        return "power"
    }

    static func parse(_ d: [String: Any]) -> Accessory? {
        guard let id = d["uniqueId"] as? String else { return nil }
        let name = (d["serviceName"] as? String) ?? "Device"
        let kind = (d["humanType"] as? String) ?? (d["type"] as? String) ?? ""
        var values: [String: Double] = [:]
        var writable = Set<String>()
        var ranges: [String: ClosedRange<Double>] = [:]
        var steps: [String: Double] = [:]
        for c in (d["serviceCharacteristics"] as? [[String: Any]]) ?? [] {
            guard let t = c["type"] as? String else { continue }
            if let n = c["value"] as? NSNumber { values[t] = n.doubleValue }
            if (c["canWrite"] as? Bool) == true { writable.insert(t) }
            if let lo = (c["minValue"] as? NSNumber)?.doubleValue,
               let hi = (c["maxValue"] as? NSNumber)?.doubleValue, lo <= hi {
                ranges[t] = lo...hi
            }
            if let s = (c["minStep"] as? NSNumber)?.doubleValue, s > 0 { steps[t] = s }
        }
        return Accessory(id: id, name: name, kind: kind, values: values,
                         writable: writable, ranges: ranges, steps: steps)
    }
}

/// Talks to the Homebridge UI (homebridge-config-ui-x) REST API.
actor HomebridgeClient {
    static let shared = HomebridgeClient()

    private var token: String?
    private var tokenExpiry = Date.distantPast
    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 10
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()

    /// Call after the connection settings change.
    func reset() { token = nil; tokenExpiry = .distantPast }

    private func baseURL() throws -> String {
        var s = Settings.serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { throw HBError.notConfigured }
        if !s.contains("://") { s = "https://" + s }
        while s.hasSuffix("/") { s.removeLast() }
        guard URL(string: s) != nil else { throw HBError.badURL }
        return s
    }

    private func raw(_ path: String, method: String, body: Data?, bearer: String?) async throws -> (Data, Int) {
        guard let url = URL(string: try baseURL() + path) else { throw HBError.badURL }
        var req = URLRequest(url: url)
        req.httpMethod = method
        if let body { req.httpBody = body; req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let bearer { req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        do {
            let (data, resp) = try await session.data(for: req)
            return (data, (resp as? HTTPURLResponse)?.statusCode ?? 0)
        } catch let e as HBError {
            throw e
        } catch {
            throw HBError.network(error.localizedDescription)
        }
    }

    private func authenticate() async throws -> String {
        if let token, tokenExpiry > Date() { return token }
        let user = Settings.username
        let (data, status): (Data, Int)
        if user.isEmpty {
            (data, status) = try await raw("/api/auth/noauth", method: "POST", body: nil, bearer: nil)
        } else {
            let body = try JSONSerialization.data(withJSONObject: ["username": user, "password": Settings.password])
            (data, status) = try await raw("/api/auth/login", method: "POST", body: body, bearer: nil)
        }
        guard status == 200 || status == 201 else {
            throw (status == 401 || status == 403 || status == 400) ? HBError.login : HBError.http(status)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let t = json["access_token"] as? String else { throw HBError.login }
        let ttl = (json["expires_in"] as? NSNumber)?.doubleValue ?? 3600
        token = t
        tokenExpiry = Date().addingTimeInterval(max(ttl - 60, 30))
        return t
    }

    private func authed(_ path: String, method: String = "GET", body: Data? = nil) async throws -> Data {
        for attempt in 0..<2 {
            let t = try await authenticate()
            let (data, status) = try await raw(path, method: method, body: body, bearer: t)
            if status == 401 && attempt == 0 { reset(); continue }
            guard (200..<300).contains(status) else { throw HBError.http(status) }
            return data
        }
        throw HBError.login
    }

    // MARK: API

    func accessories() async throws -> [Accessory] {
        let data = try await authed("/api/accessories")
        guard let list = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return list.compactMap(Accessory.parse)
    }

    func accessory(id: String) async throws -> Accessory {
        guard let a = try await accessories().first(where: { $0.id == id }) else { throw HBError.notFound }
        return a
    }

    private static let intKeys: Set<String> = ["Active", "TargetHeaterCoolerState", "TargetHeatingCoolingState"]

    func set(id: String, key: String, value: Double) async throws {
        let json: Any
        if key == "On" { json = value != 0 }
        else if Self.intKeys.contains(key) { json = Int(value) }
        else { json = value }
        let body = try JSONSerialization.data(withJSONObject: ["characteristicType": key, "value": json])
        _ = try await authed("/api/accessories/\(id)", method: "PUT", body: body)
    }
}
