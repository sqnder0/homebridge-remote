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
    @Parameter(title: "Temperature", description: "Degrees Celsius",
               requestValueDialog: "To how many degrees?")
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

// MARK: - Fixed airco intents (phrases without a device name are more reliable for Siri)

/// The airco on the home screen, or else the first one Homebridge has.
private func mainAirco() async throws -> Accessory {
    let all = try await HomebridgeClient.shared.accessories()
    let saved = Set(DeviceStore.load().map(\.id))
    if let a = all.first(where: { $0.isHeaterCooler && saved.contains($0.id) })
        ?? all.first(where: { $0.isHeaterCooler }) {
        return a
    }
    throw HBError.notFound
}

struct AircoOnIntent: AppIntent {
    static let title: LocalizedStringResource = "Turn On Airco"
    static let description = IntentDescription("Turns the air conditioner on.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let a = try await mainAirco()
        try await HomebridgeClient.shared.set(id: a.id, key: "Active", value: 1)
        return .result(dialog: "The airco is on.")
    }
}

struct AircoOffIntent: AppIntent {
    static let title: LocalizedStringResource = "Turn Off Airco"
    static let description = IntentDescription("Turns the air conditioner off.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let a = try await mainAirco()
        try await HomebridgeClient.shared.set(id: a.id, key: "Active", value: 0)
        return .result(dialog: "The airco is off.")
    }
}

struct AircoTemperatureIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Airco Temperature"
    static let description = IntentDescription("Sets the air conditioner's target temperature.")

    @Parameter(title: "Temperature", description: "Degrees Celsius",
               requestValueDialog: "To how many degrees?")
    var temperature: Int

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let client = HomebridgeClient.shared
        let a = try await mainAirco()
        guard let key = a.targetKey else { throw HBError.unsupported("The airco") }
        let range = a.ranges[key] ?? 16...30
        let value = min(max(Double(temperature), range.lowerBound), range.upperBound)
        if !a.isOn { try await client.set(id: a.id, key: "Active", value: 1) }
        try await client.set(id: a.id, key: key, value: value)
        return .result(dialog: "The airco is set to \(Int(value)) degrees.")
    }
}

// MARK: - Siri phrases

struct HomebridgeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AircoOnIntent(),
            phrases: [
                "Turn on the airco in \(.applicationName)",
                "Turn on airco in \(.applicationName)",
                "Turn the airco on in \(.applicationName)",
                "Turn on the air conditioner in \(.applicationName)",
                "Turn on the airco with \(.applicationName)",
                "\(.applicationName) airco on",
            ],
            shortTitle: "Airco On",
            systemImageName: "power.circle.fill"
        )
        AppShortcut(
            intent: AircoOffIntent(),
            phrases: [
                "Turn off the airco in \(.applicationName)",
                "Turn off airco in \(.applicationName)",
                "Turn the airco off in \(.applicationName)",
                "Turn off the air conditioner in \(.applicationName)",
                "Turn off the airco with \(.applicationName)",
                "\(.applicationName) airco off",
            ],
            shortTitle: "Airco Off",
            systemImageName: "power.circle"
        )
        AppShortcut(
            intent: AircoTemperatureIntent(),
            phrases: [
                "Set the airco temperature in \(.applicationName)",
                "Change the airco temperature in \(.applicationName)",
                "Set the airco temperature with \(.applicationName)",
            ],
            shortTitle: "Airco Temperature",
            systemImageName: "thermometer.medium"
        )
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
