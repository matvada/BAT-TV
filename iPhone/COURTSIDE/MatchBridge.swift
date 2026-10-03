import Foundation
import Combine
@preconcurrency import CoreBluetooth

/// BLE GATT peripheral. No HTTP, WebKit, account, LAN, or cloud service.
/// Encrypted GATT characteristics plus a fresh on-screen application pairing code.
@MainActor
final class MatchBridge: NSObject, ObservableObject, CBPeripheralManagerDelegate {
    static let serviceID = CBUUID(string: "BA7A0001-9130-4D77-A6E0-BA7A20140001")
    static let commandID = CBUUID(string: "BA7A0002-9130-4D77-A6E0-BA7A20140001")
    static let stateID = CBUUID(string: "BA7A0003-9130-4D77-A6E0-BA7A20140001")
    @Published private(set) var pin = String(format: "%06d", Int.random(in: 0...999999))
    @Published private(set) var status = "Regia Bluetooth disattivata"
    @Published private(set) var game: Game
    @Published private(set) var linked = false
    var onLiveCommand: ((Bool) -> Void)?
    var onEvent: (([String: Any]) -> Void)?
    private var browser: CBCentralManager?
    private var remote: CBPeripheral?
    private var devices: [UUID: CBPeripheral] = [:]
    private var remoteRX: CBCharacteristic?
    private var remoteTX: CBCharacteristic?
    private var clientWrites: [Data] = []
    private var writing = false
    private var clientInput = Data()
    private var isCamera = true
    private var manager: CBPeripheralManager?
    private var tx: CBMutableCharacteristic?
    private var central: CBCentral?
    private var authenticated = false
    private var input = Data()
    private var packets: [Data] = []
    private var history: [Game] = []
    private var seen: [String] = []
    private var revision = 0
    private var timer: Timer?
    private var wantsAdvertising = false
    private var cameraReady = false
    private var publishing = false
    private var failures = 0
    private var lockedUntil = Date.distantPast

    override init() {
        let now = Date().timeIntervalSince1970 * 1000
        if let data = UserDefaults.standard.data(forKey: "batLocalGame"), var saved = try? JSONDecoder().decode(Game.self, from: data) {
            saved.clock = Double(saved.remaining(at: now)); saved.running = false; saved.live = false
            game = saved
        } else { game = .fresh(now: now) }
        super.init()
    }

    func startController() {
        stop(); isCamera = false
        browser = CBCentralManager(delegate: self, queue: .main)
    }

    func start() {
        isCamera = true
        wantsAdvertising = true
        if let manager {
            if manager.state == .poweredOn { advertise() }
        } else { manager = CBPeripheralManager(delegate: self, queue: .main) }
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
        }
    }

    func stop() {
        wantsAdvertising = false
        browser?.stopScan()
        if let remote { browser?.cancelPeripheralConnection(remote) }
        browser = nil; remote = nil; devices.removeAll(); clientWrites.removeAll(); writing = false; clientInput.removeAll()
        manager?.stopAdvertising()
        manager?.removeAllServices()
        manager = nil; tx = nil; central = nil; authenticated = false; linked = false
        packets.removeAll(); input.removeAll(); timer?.invalidate(); timer = nil
        status = "Regia Bluetooth disattivata"
        pin = String(format: "%06d", Int.random(in: 0...999999))
    }

    func setCameraStatus(ready: Bool, publishing: Bool) {
        cameraReady = ready; self.publishing = publishing
        game.live = publishing
        sendState()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(game) { UserDefaults.standard.set(data, forKey: "batLocalGame") }
    }

    private func tick() {
        if game.running && game.remaining(at: now()) == 0 {
            game.running = false; game.clock = 0; revision += 1; save()
        }
        // Don't append another snapshot while the BLE radio is still draining one.
        if packets.isEmpty { sendState() }
    }

    private func now() -> Double { Date().timeIntervalSince1970 * 1000 }

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        guard peripheral.state == .poweredOn else {
            linked = false; authenticated = false; central = nil; packets.removeAll(); input.removeAll()
            tx = nil
            status = peripheral.state == .unauthorized ? "Consenti Bluetooth nelle Impostazioni" : "Attiva Bluetooth sull’iPhone"
            return
        }
        let rx = CBMutableCharacteristic(type: Self.commandID, properties: [.write], value: nil, permissions: [.writeEncryptionRequired])
        let output = CBMutableCharacteristic(type: Self.stateID, properties: [.notifyEncryptionRequired], value: nil, permissions: [.readEncryptionRequired])
        tx = output
        let service = CBMutableService(type: Self.serviceID, primary: true)
        service.characteristics = [rx, output]
        peripheral.add(service)
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error { status = "Bluetooth: \(error.localizedDescription)"; return }
        if wantsAdvertising { advertise() }
    }

    private func advertise() {
        guard tx != nil else { return }
        manager?.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [Self.serviceID], CBAdvertisementDataLocalNameKey: "BAT tv iPhone"])
        status = "Apri BAT tv Regia sul tablet e inserisci il codice"
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        guard characteristic.uuid == Self.stateID, self.central == nil || self.central?.identifier == central.identifier else { return }
        self.central = central; authenticated = false; linked = false
        packets.removeAll(); input.removeAll()
        send(["type": "hello", "protocol": 1])
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        guard self.central?.identifier == central.identifier else { return }
        self.central = nil; authenticated = false; linked = false
        packets.removeAll(); input.removeAll()
        status = "Tablet scollegato · la partita continua sull’iPhone"
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            guard request.characteristic.uuid == Self.commandID, request.offset == 0,
                  central?.identifier == request.central.identifier, let value = request.value else {
                peripheral.respond(to: request, withResult: .insufficientAuthorization); continue
            }
            guard input.count + value.count <= 8192 else {
                input.removeAll(); peripheral.respond(to: request, withResult: .invalidAttributeValueLength); continue
            }
            input.append(value)
            peripheral.respond(to: request, withResult: .success)
            while let delimiter = input.firstIndex(of: 10) {
                let line = input.prefix(upTo: delimiter)
                input.removeSubrange(...delimiter)
                receive(Data(line))
            }
        }
    }

    func localCommand(_ object: [String: Any]) {
        guard isCamera, let data = try? JSONSerialization.data(withJSONObject: object) else { return }
        let previous = authenticated; authenticated = true; receive(data); authenticated = previous
    }

    private func receive(_ data: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String else { return }
        if type == "pair" {
            guard Date() >= lockedUntil else { send(["type": "error", "message": "Attendi 30 secondi prima di riprovare"]); return }
            guard object["pin"] as? String == pin else {
                failures += 1
                if failures >= 5 { lockedUntil = Date().addingTimeInterval(30); failures = 0 }
                send(["type": "error", "message": "Codice errato"]); return
            }
            authenticated = true; linked = true; failures = 0
            status = "Tablet collegato via Bluetooth"
            sendState(); return
        }
        guard authenticated else { send(["type": "error", "message": "Inserisci prima il codice dell’iPhone"]); return }
        guard type == "command", let id = object["id"] as? String, id.count <= 64,
              let action = object["action"] as? String else { return }
        if seen.contains(id) { send(["type": "ack", "id": id]); return }
        var accepted = true
        if action == "liveStart" || action == "liveStop" {
            onLiveCommand?(action == "liveStart")
        } else if action == "undo" {
            if var previous = history.popLast() {
                previous.clock = Double(previous.remaining(at: now())); previous.running = false; previous.live = publishing
                game = previous
            }
        } else {
            var next = game
            accepted = next.apply(action, team: object["team"] as? String, value: object["value"] as? Int, text: object["text"] as? String, now: now())
            if accepted {
                history.append(game); if history.count > 30 { history.removeFirst() }; game = next
            }
        }
        guard accepted else { send(["type": "error", "message": "Comando non valido"]); return }
        seen.append(id); if seen.count > 100 { seen.removeFirst() }
        revision += 1; save()
        send(["type": "ack", "id": id]); sendState()
    }

    private func sendState() {
        guard let encoded = try? JSONEncoder().encode(game),
              let state = try? JSONSerialization.jsonObject(with: encoded) else { return }
        let snapshot: [String: Any] = ["type": "state", "state": state, "revision": revision, "serverNow": now(), "cameraReady": cameraReady, "publishing": publishing]
        onEvent?(snapshot)
        if authenticated { send(snapshot) }
    }

    private func send(_ value: [String: Any]) {
        guard let central, let bytes = try? JSONSerialization.data(withJSONObject: value) else { return }
        let data = bytes + Data([10])
        let maximum = max(1, min(central.maximumUpdateValueLength, 180))
        guard packets.count < 500 else { return }
        for offset in stride(from: 0, to: data.count, by: maximum) {
            packets.append(data.subdata(in: offset..<min(offset + maximum, data.count)))
        }
        onEvent?(value)
        flush()
    }

    private func flush() {
        guard let manager, let tx, let central else { return }
        while let packet = packets.first {
            guard manager.updateValue(packet, for: tx, onSubscribedCentrals: [central]) else { return }
            packets.removeFirst()
        }
    }

    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) { flush() }
}

extension MatchBridge: CBCentralManagerDelegate, CBPeripheralDelegate {
    func centralManagerDidUpdateState(_ manager: CBCentralManager) {
        guard manager.state == .poweredOn else { status = "Attiva Bluetooth e consenti l’accesso nelle Impostazioni"; return }
        scan()
    }

    func scan() {
        guard let browser, browser.state == .poweredOn else { status = "Bluetooth non pronto"; return }
        browser.scanForPeripherals(withServices: [Self.serviceID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        status = "Cerco BAT tv Camera nelle vicinanze…"
    }

    func centralManager(_ manager: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        devices[peripheral.identifier] = peripheral
        onEvent?(["type": "device", "name": advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? "BAT tv Camera", "address": peripheral.identifier.uuidString])
    }

    func connect(_ id: String) {
        guard let uuid = UUID(uuidString: id), let found = devices[uuid] else { status = "Cerca di nuovo la Camera"; return }
        browser?.stopScan(); remote = found; found.delegate = self
        browser?.connect(found); status = "Collegamento Bluetooth…"
    }

    func centralManager(_ manager: CBCentralManager, didConnect peripheral: CBPeripheral) { peripheral.discoverServices([Self.serviceID]) }
    func centralManager(_ manager: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) { linked = false; status = "Collegamento fallito · riprova" }
    func centralManager(_ manager: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        linked = false; remote = nil; remoteRX = nil; remoteTX = nil; clientWrites.removeAll(); writing = false; clientInput.removeAll()
        status = "Bluetooth scollegato · premi Cerca per ricollegarti"
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let service = peripheral.services?.first(where: { $0.uuid == Self.serviceID }) else { status = "Servizio BAT tv non disponibile"; return }
        peripheral.discoverCharacteristics([Self.commandID, Self.stateID], for: service)
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil else { status = "Scoperta Bluetooth fallita"; return }
        remoteRX = service.characteristics?.first(where: { $0.uuid == Self.commandID })
        remoteTX = service.characteristics?.first(where: { $0.uuid == Self.stateID })
        if let remoteTX { peripheral.setNotifyValue(true, for: remoteTX) }
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        status = error == nil ? "Bluetooth pronto · inserisci il codice della Camera" : "Conferma l’abbinamento Bluetooth e riprova"
    }
    func sendCommand(_ value: [String: Any]) {
        guard let remote, let remoteRX, let bytes = try? JSONSerialization.data(withJSONObject: value) else { status = "Collega prima la Camera"; return }
        let payload = bytes + Data([10]); let length = max(1, min(remote.maximumWriteValueLength(for: .withResponse), 180))
        guard clientWrites.count < 500 else { status = "Bluetooth occupato · attendi"; return }
        for offset in stride(from: 0, to: payload.count, by: length) { clientWrites.append(payload.subdata(in: offset..<min(offset + length, payload.count))) }
        flushClient(remote, remoteRX)
    }
    private func flushClient(_ peripheral: CBPeripheral, _ characteristic: CBCharacteristic) {
        guard !writing, let data = clientWrites.first else { return }
        writing = true; peripheral.writeValue(data, for: characteristic, type: .withResponse)
    }
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        writing = false
        if let error { clientWrites.removeAll(); status = "Comando non inviato: \(error.localizedDescription)"; return }
        if !clientWrites.isEmpty { clientWrites.removeFirst() }
        if let remoteRX { flushClient(peripheral, remoteRX) }
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, characteristic.uuid == Self.stateID, let data = characteristic.value else { return }
        guard clientInput.count + data.count < 8192 else { clientInput.removeAll(); return }
        clientInput.append(data)
        while let delimiter = clientInput.firstIndex(of: 10) {
            let line = Data(clientInput.prefix(upTo: delimiter)); clientInput.removeSubrange(...delimiter)
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            if object["type"] as? String == "state", let state = object["state"], let data = try? JSONSerialization.data(withJSONObject: state), let snapshot = try? JSONDecoder().decode(Game.self, from: data) {
                game = snapshot; linked = true; status = "Collegato via Bluetooth"
            }
            onEvent?(object)
        }
    }
}
