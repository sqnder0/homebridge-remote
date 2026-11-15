import AppIntents

// MARK: - Entity: one per device the user added in the app

struct DeviceEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Device"
    static let defaultQuery = DeviceQuery()

    let id: String
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    init(_ device: SavedDevice) {
        id = device.id
        name = device.name
    }
}

struct DeviceQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [DeviceEntity] {
        DeviceStore.load().filter { identifiers.contains($0.id) }.map(DeviceEntity.init)
    }

    func suggestedEntities() async throws -> [DeviceEntity] {
        DeviceStore.load().map(DeviceEntity.init)
    }

    func entities(matching string: String) async throws -> [DeviceEntity] {
        DeviceStore.load()
            .filter { $0.name.localizedCaseInsensitiveContains(string) }
            .map(DeviceEntity.init)
    }
}

// MARK: - Intents (these run without opening the app)

private func setPower(_ entity: DeviceEntity, on: Bool) async throws {
    guard let device = DeviceStore.device(id: entity.id) else { throw HBError.notFound }
    try await HomebridgeClient.shared.set(id: device.id, key: device.characteristic, value: on ? 1 : 0)
}

struct TurnOnDeviceIntent: AppIntent {
    static let title: LocalizedStringResource = "Turn On"
    static let description = IntentDescription("Turns a device on.")

    @Parameter(title: "Device") var device: DeviceEntity

    static var parameterSummary: some ParameterSummary { Summary("Turn on \(\.$device)") }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await setPower(device, on: true)
        return .result(dialog: "\(device.name) is on.")
    }
}

struct TurnOffDeviceIntent: AppIntent {
    static let title: LocalizedStringResource = "Turn Off"
    static let description = IntentDescription("Turns a device off.")

    @Parameter(title: "Device") var device: DeviceEntity

    static var parameterSummary: some ParameterSummary { Summary("Turn off \(\.$device)") }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await setPower(device, on: false)
        return .result(dialog: "\(device.name) is off.")
    }
}

struct SetTemperatureIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Temperature"
    static let description = IntentDescription("Sets the target temperature of an air conditioner or thermostat.")

    @Parameter(title: "Device") var device: DeviceEntity
    @Parameter(title: "Temperature", description: "Degrees Celsius")
    var temperature: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Set \(\.$device) to \(\.$temperature) degrees")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let client = HomebridgeClient.shared
        let acc = try await client.accessory(id: device.id)
        guard let key = acc.targetKey else { throw HBError.unsupported(device.name) }
        let range = acc.ranges[key] ?? 16...30
        let value = min(max(Double(temperature), range.lowerBound), range.upperBound)
        if !acc.isOn, let power = acc.powerKey {
            try await client.set(id: acc.id, key: power, value: 1)
        }
        try await client.set(id: acc.id, key: key, value: value)
        return .result(dialog: "\(device.name) is set to \(Int(value)) degrees.")
    }
}

// MARK: - Siri phrases

struct HomebridgeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TurnOnDeviceIntent(),
            phrases: [
                "Turn on \(\.$device) in \(.applicationName)",
                "Switch on \(\.$device) in \(.applicationName)",
            ],
            shortTitle: "Turn On",
            systemImageName: "power.circle.fill"
        )
        AppShortcut(
            intent: TurnOffDeviceIntent(),
            phrases: [
                "Turn off \(\.$device) in \(.applicationName)",
                "Switch off \(\.$device) in \(.applicationName)",
            ],
            shortTitle: "Turn Off",
            systemImageName: "power.circle"
        )
        AppShortcut(
            intent: SetTemperatureIntent(),
            phrases: [
                "Set the temperature of \(\.$device) in \(.applicationName)",
            ],
            shortTitle: "Set Temperature",
            systemImageName: "thermometer.medium"
        )
    }
}
