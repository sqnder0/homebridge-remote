import SwiftUI
import AppIntents

struct Write {
    let id: String
    let key: String
    let value: Double
}

/// App-wide state: the devices the user added, plus their live status.
@MainActor @Observable
final class Hub {
    var saved: [SavedDevice] = DeviceStore.load()
    var live: [String: Accessory] = [:]
    var discovered: [Accessory] = []
    var error: String?

    /// Values we just sent. Homebridge needs a moment to report them back, so
    /// polling must not snap the UI back to the old value in the meantime.
    private var pending: [String: (value: Double, until: Date)] = [:]

    func refresh() async {
        do {
            var all = try await HomebridgeClient.shared.accessories()
            let now = Date()
            pending = pending.filter { $0.value.until > now }
            for i in all.indices {
                for (k, p) in pending {
                    let prefix = all[i].id + "|"
                    if k.hasPrefix(prefix) { all[i].values[String(k.dropFirst(prefix.count))] = p.value }
                }
            }
            discovered = all
            live = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            error = nil
            adoptAirco()
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: Managing devices

    func isAdded(_ id: String) -> Bool { saved.contains { $0.id == id } }

    func add(_ acc: Accessory) {
        guard !isAdded(acc.id) else { return }
        saved.append(SavedDevice(id: acc.id, name: acc.name, characteristic: acc.powerKey ?? "On"))
        persist()
    }

    func remove(_ id: String) {
        saved.removeAll { $0.id == id }
        persist()
    }

    func rename(_ id: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let i = saved.firstIndex(where: { $0.id == id }) else { return }
        saved[i].name = trimmed
        persist()
    }

    /// IDs of helper services that are shown inside an airco card instead of on their own.
    var aircoMemberIDs: Set<String> {
        var ids = Set<String>()
        for main in live.values where main.isHeaterCooler {
            ids.formUnion(Airco(main: main, all: Array(live.values)).memberIDs.subtracting([main.id]))
        }
        return ids
    }

    /// First run with an airco: put it on the home screen (named "Airco" for Siri)
    /// and drop its helper services, which now live inside the airco card.
    private func adoptAirco() {
        let flag = "aircoAdopted"
        guard !UserDefaults.standard.bool(forKey: flag),
              let main = live.values.first(where: { $0.isHeaterCooler }) else { return }
        let members = aircoMemberIDs
        saved.removeAll { members.contains($0.id) }
        if !isAdded(main.id) {
            saved.insert(SavedDevice(id: main.id, name: "Airco", characteristic: "Active"), at: 0)
        }
        persist()
        UserDefaults.standard.set(true, forKey: flag)
    }

    private func persist() {
        DeviceStore.save(saved)
        // Tell Siri about the new device list so phrases like
        // "Turn on <device> in Homebridge Remote" keep working.
        HomebridgeShortcuts.updateAppShortcutParameters()
    }

    // MARK: Control (optimistic: update the UI first, then send)

    func setPower(_ id: String, on: Bool) {
        guard let key = live[id]?.powerKey ?? saved.first(where: { $0.id == id })?.characteristic else { return }
        send(id, key, on ? 1 : 0)
    }

    func send(_ id: String, _ key: String, _ value: Double) {
        sendAll([Write(id: id, key: key, value: value)])
    }

    /// Show a value locally without sending it (for side effects Homebridge applies itself).
    func assume(_ id: String, _ key: String, _ value: Double) {
        live[id]?.values[key] = value
        pending["\(id)|\(key)"] = (value, Date().addingTimeInterval(8))
    }

    /// Sends writes one after another, in order.
    func sendAll(_ writes: [Write]) {
        guard !writes.isEmpty else { return }
        for w in writes { assume(w.id, w.key, w.value) }
        Task {
            do {
                for w in writes {
                    try await HomebridgeClient.shared.set(id: w.id, key: w.key, value: w.value)
                }
            } catch {
                self.error = error.localizedDescription
                self.pending.removeAll()
                await self.refresh()
            }
        }
    }
}
