import SwiftUI
import AppIntents

/// App-wide state: the devices the user added, plus their live status.
@MainActor @Observable
final class Hub {
    var saved: [SavedDevice] = DeviceStore.load()
    var live: [String: Accessory] = [:]
    var discovered: [Accessory] = []
    var error: String?

    func refresh() async {
        do {
            let all = try await HomebridgeClient.shared.accessories()
            discovered = all
            live = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            error = nil
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
        live[id]?.values[key] = value
        Task {
            do {
                try await HomebridgeClient.shared.set(id: id, key: key, value: value)
            } catch {
                self.error = error.localizedDescription
                await self.refresh()
            }
        }
    }
}
