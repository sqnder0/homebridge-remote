import SwiftUI

struct RootView: View {
    @Environment(Hub.self) private var hub
    @Environment(\.scenePhase) private var phase
    @State private var showAdd = false
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ZStack {
                Backdrop()
                ScrollView {
                    LazyVStack(spacing: 18) {
                        if let error = hub.error {
                            Label(error, systemImage: "wifi.exclamationmark")
                                .font(.footnote)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 16).fill(.red.opacity(0.25)))
                        }
                        if hub.saved.isEmpty {
                            EmptyState { showAdd = true }
                        } else {
                            ForEach(hub.saved) { DeviceCard(saved: $0) }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
                }
                .refreshable { await hub.refresh() }
            }
            .navigationTitle("Home")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Settings", systemImage: "gearshape") { showSettings = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add device", systemImage: "plus.circle.fill") { showAdd = true }
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showAdd) { AddDevicesView() }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .onAppear { if !Settings.configured { showSettings = true } }
        // Poll while the app is in the foreground; cancelled automatically otherwise.
        .task(id: phase) {
            guard phase == .active else { return }
            while !Task.isCancelled {
                await hub.refresh()
                try? await Task.sleep(for: .seconds(4))
            }
        }
    }
}

struct EmptyState: View {
    var add: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "air.conditioner.horizontal.fill")
                .font(.system(size: 54))
                .foregroundStyle(.cyan)
            Text("No devices yet").font(.title3.weight(.semibold))
            Text("Add your airco or any other Homebridge device. Everything you add can be controlled with Siri.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Add a device", action: add)
                .buttonStyle(.borderedProminent).tint(.cyan).controlSize(.large)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .background(CardBackground(tint: .cyan))
        .padding(.top, 40)
    }
}

// MARK: - Add devices

struct AddDevicesView: View {
    @Environment(Hub.self) private var hub
    @Environment(\.dismiss) private var dismiss

    private var controllable: [Accessory] {
        hub.discovered
            .filter { $0.powerKey != nil || $0.targetKey != nil }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List {
                if let error = hub.error {
                    Text(error).foregroundStyle(.red)
                }
                ForEach(controllable) { acc in
                    let added = hub.isAdded(acc.id)
                    Button {
                        added ? hub.remove(acc.id) : hub.add(acc)
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: acc.symbol).frame(width: 30).foregroundStyle(.cyan)
                            VStack(alignment: .leading) {
                                Text(acc.name).foregroundStyle(.primary)
                                Text(acc.kind).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: added ? "checkmark.circle.fill" : "plus.circle")
                                .font(.title3)
                                .foregroundStyle(added ? .green : .secondary)
                        }
                    }
                }
            }
            .overlay {
                if controllable.isEmpty && hub.error == nil {
                    ContentUnavailableView("Nothing found", systemImage: "magnifyingglass",
                                           description: Text("Pull down to refresh."))
                }
            }
            .navigationTitle("Add devices")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .refreshable { await hub.refresh() }
            .task { await hub.refresh() }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Settings

struct SettingsView: View {
    @Environment(Hub.self) private var hub
    @Environment(\.dismiss) private var dismiss
    @State private var url = Settings.serverURL
    @State private var user = Settings.username
    @State private var pass = Settings.password
    @State private var result: String?
    @State private var testing = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://homebridge.example.com", text: $url)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Username", text: $user)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Password", text: $pass)
                } header: {
                    Text("Homebridge")
                } footer: {
                    Text("The same address and login you use for the Homebridge web interface. Leave the username empty if Homebridge has no login.")
                }

                Section {
                    Button {
                        Task { await saveAndTest() }
                    } label: {
                        HStack {
                            Text("Save & test connection")
                            if testing { Spacer(); ProgressView() }
                        }
                    }
                    if let result { Text(result).font(.footnote) }
                }

                Section("Using Siri") {
                    Text("Say “Hey Siri, turn on **Airco** in **Homebridge Remote**”, using the name of any device you added. Rename a device (long-press its card) to change what Siri listens for.")
                    Text("For a shorter phrase, open the Shortcuts app, add the action “Turn On” from Homebridge Remote and name the shortcut, for example “Airco aan”. Then just say “Hey Siri, Airco aan”.")
                }
                .font(.footnote)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }

    private func saveAndTest() async {
        testing = true
        defer { testing = false }
        Settings.serverURL = url
        Settings.username = user
        Settings.password = pass
        Settings.configured = true
        await HomebridgeClient.shared.reset()
        await hub.refresh()
        if let error = hub.error {
            result = "✗ " + error
        } else {
            result = "✓ Connected. Found \(hub.discovered.count) accessories."
        }
    }
}
