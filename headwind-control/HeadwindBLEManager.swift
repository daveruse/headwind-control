//
//  HeadwindBLEManager.swift
//  headwind-control
//
//  Created by Dave Ruse on 8/20/26.
//

import Combine
import CoreBluetooth
import Foundation

/// BLE control for Wahoo KICKR HEADWIND (reverse-engineered protocol).
final class HeadwindBLEManager: NSObject, ObservableObject {
    static let serviceUUID = CBUUID(string: "A026EE0C-0A7D-4AB3-97FA-F1500F9FEB8B")
    static let commandUUID = CBUUID(string: "A026E038-0A7D-4AB3-97FA-F1500F9FEB8B")
    static let deviceNamePrefix = "HEADWIND"

    enum ConnectionState: Equatable {
        case poweredOff
        case idle
        case scanning
        case connecting
        case connected
        case error(String)
    }

    @Published private(set) var connectionState: ConnectionState = .idle
    @Published private(set) var isOn = false {
        didSet { HeadwindShared.defaults.set(isOn, forKey: HeadwindShared.isOnKey) }
    }
    @Published private(set) var speed: Int = 0
    @Published var targetSpeed: Int = 50

    var statusIcon: String {
        switch connectionState {
        case .connected where isOn:
            return "wind"
        case .connected:
            return "wind"
        case .scanning, .connecting:
            return "antenna.radiowaves.left.and.right"
        case .poweredOff, .error:
            return "wind.circle"
        default:
            return "wind.circle"
        }
    }

    var statusText: String {
        switch connectionState {
        case .poweredOff:
            return "Bluetooth is off"
        case .idle:
            return "Tap Connect"
        case .scanning:
            return "Searching for HEADWIND…"
        case .connecting:
            return "Connecting…"
        case .connected:
            return isOn ? "On · \(speed)%" : "Off"
        case .error(let message):
            return message
        }
    }

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var commandCharacteristic: CBCharacteristic?
    private var pendingSpeed: Int?
    private var needsManualMode = true
    private var speedDebounceTask: Task<Void, Never>?
    private var pendingWriteCompletion: (() -> Void)?

    /// Shared with the Control Center widget extension via an App Group, so both sides
    /// reconnect to the same fan without a fresh scan.
    private var savedPeripheralID: UUID? {
        get {
            HeadwindShared.defaults.string(forKey: HeadwindShared.peripheralIDKey).flatMap(UUID.init(uuidString:))
        }
        set {
            HeadwindShared.defaults.set(newValue?.uuidString, forKey: HeadwindShared.peripheralIDKey)
        }
    }

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    func connect() {
        guard central.state == .poweredOn else {
            connectionState = .poweredOff
            return
        }
        if peripheral != nil, connectionState == .connected {
            return
        }
        if let savedID = savedPeripheralID {
            reconnect(to: savedID)
        } else {
            startScan()
        }
    }

    /// Turns the fan off when connected, then closes the BLE link.
    func disconnect(completion: (() -> Void)? = nil) {
        guard connectionState == .connected, commandCharacteristic != nil else {
            performDisconnect()
            completion?()
            return
        }

        turnOff()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.performDisconnect()
            completion?()
        }
    }

    func turnOn(speed: Int? = nil) {
        let value = speed ?? targetSpeed
        targetSpeed = max(1, min(100, value))
        guard connectionState == .connected else { return }
        needsManualMode = true
        sendManualModeThenSpeed(targetSpeed)
    }

    func turnOff() {
        guard connectionState == .connected else {
            isOn = false
            speed = 0
            return
        }
        writeCommand([0x04, 0x01, 0x00, 0x00]) { [weak self] in
            self?.isOn = false
            self?.speed = 0
            self?.needsManualMode = true
        }
    }

    func setSpeed(_ value: Int, debounce: Bool = true) {
        let clamped = max(0, min(100, value))
        targetSpeed = clamped == 0 ? 1 : clamped

        speedDebounceTask?.cancel()
        guard connectionState == .connected else { return }

        let apply = { [weak self] in
            guard let self else { return }
            if clamped == 0 {
                self.turnOff()
                return
            }
            if !self.isOn {
                self.turnOn(speed: clamped)
                return
            }
            if self.needsManualMode {
                self.sendManualModeThenSpeed(clamped)
            } else {
                self.writeSpeed(clamped)
            }
        }

        if debounce {
            speedDebounceTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard !Task.isCancelled else { return }
                apply()
            }
        } else {
            apply()
        }
    }

    func applyPreset(_ percent: Int) {
        targetSpeed = percent
        setSpeed(percent, debounce: false)
    }

    // MARK: - Private

    private func startScan() {
        peripheral = nil
        commandCharacteristic = nil
        connectionState = .scanning
        // Service UUID is not in the advertisement packet — scan by name instead.
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
            guard let self, self.connectionState == .scanning else { return }
            self.central.stopScan()
            self.connectionState = .error("HEADWIND not found")
        }
    }

    /// Reconnects to a previously-seen peripheral by identifier, skipping the scan.
    /// `connect(_:)` on a known-but-unreachable peripheral never calls `didFailToConnect` —
    /// it just waits — so a timeout falls back to a fresh scan if it doesn't pan out.
    private func reconnect(to savedID: UUID) {
        guard let known = central.retrievePeripherals(withIdentifiers: [savedID]).first else {
            startScan()
            return
        }
        peripheral = known
        commandCharacteristic = nil
        known.delegate = self
        connectionState = .connecting
        central.connect(known, options: nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, self.peripheral === known, self.connectionState == .connecting else { return }
            self.central.cancelPeripheralConnection(known)
            self.peripheral = nil
            self.startScan()
        }
    }

    private func sendManualModeThenSpeed(_ value: Int) {
        pendingSpeed = value
        writeCommand([0x04, 0x04, 0x00, 0x00]) { [weak self] in
            guard let self, let pending = self.pendingSpeed else { return }
            self.needsManualMode = false
            self.pendingSpeed = nil
            self.writeSpeed(pending)
        }
    }

    private func writeSpeed(_ value: Int) {
        let clamped = UInt8(max(1, min(100, value)))
        writeCommand([0x02, clamped, 0x00, 0x00]) { [weak self] in
            self?.isOn = true
            self?.speed = Int(clamped)
            self?.targetSpeed = Int(clamped)
        }
    }

    /// Writes a command and defers `completion` until the peripheral confirms via
    /// `didWriteValueFor` when using `.withResponse`; `.withoutResponse` writes have no
    /// confirmation to wait for, so `completion` runs right after the write is queued.
    private func writeCommand(_ bytes: [UInt8], completion: (() -> Void)? = nil) {
        guard let peripheral,
              let characteristic = commandCharacteristic else { return }
        let data = Data(bytes)
        let writeType: CBCharacteristicWriteType =
            characteristic.properties.contains(.write) ? .withResponse : .withoutResponse

        if writeType == .withResponse {
            pendingWriteCompletion = completion
        }
        peripheral.writeValue(data, for: characteristic, type: writeType)
        if writeType == .withoutResponse {
            completion?()
        }
    }

    private func performDisconnect() {
        if let peripheral {
            central.cancelPeripheralConnection(peripheral)
        }
        resetConnection()
        connectionState = .idle
    }

    private func resetConnection() {
        central.stopScan()
        peripheral = nil
        commandCharacteristic = nil
        needsManualMode = true
        pendingSpeed = nil
        pendingWriteCompletion = nil
        speedDebounceTask?.cancel()
    }

    private func parseNotification(_ data: Data) {
        let bytes = [UInt8](data)
        guard bytes.count >= 4 else { return }

        switch bytes[0] {
        case 0xfd:
            let mode = bytes[3]
            switch mode {
            case 0x01:
                isOn = false
                speed = 0
            case 0x04:
                isOn = true
                speed = Int(bytes[2])
                targetSpeed = speed
            case 0x02, 0x03, 0x05:
                isOn = mode != 0x05
            default:
                break
            }
        case 0xfe where bytes[1] == 0x02:
            isOn = true
            speed = Int(bytes[3])
            targetSpeed = speed
        case 0xfe where bytes[1] == 0x04 && bytes[3] == 0x01:
            isOn = false
            speed = 0
        default:
            break
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension HeadwindBLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            if connectionState == .poweredOff {
                connectionState = .idle
            }
        case .poweredOff:
            connectionState = .poweredOff
            resetConnection()
        case .unauthorized:
            connectionState = .error("Bluetooth permission denied")
        default:
            connectionState = .error("Bluetooth unavailable")
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let name = peripheral.name
            ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? ""
        guard name.uppercased().hasPrefix(Self.deviceNamePrefix) else { return }

        central.stopScan()
        self.peripheral = peripheral
        savedPeripheralID = peripheral.identifier
        peripheral.delegate = self
        connectionState = .connecting
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectionState = .connected
        peripheral.discoverServices([Self.serviceUUID])
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        resetConnection()
        connectionState = .error(error?.localizedDescription ?? "Connection failed")
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        resetConnection()
        isOn = false
        speed = 0
        connectionState = error == nil ? .idle : .error("Connection lost")
    }
}

// MARK: - CBPeripheralDelegate

extension HeadwindBLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else {
            connectionState = .error(error!.localizedDescription)
            return
        }
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.serviceUUID }) else {
            connectionState = .error("Service not found")
            return
        }
        peripheral.discoverCharacteristics([Self.commandUUID], for: service)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard error == nil,
              let characteristic = service.characteristics?.first(where: { $0.uuid == Self.commandUUID })
        else {
            connectionState = .error("Characteristic not found")
            return
        }
        commandCharacteristic = characteristic
        peripheral.setNotifyValue(true, for: characteristic)
        peripheral.readValue(for: characteristic)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard characteristic.uuid == Self.commandUUID,
              let data = characteristic.value else { return }
        DispatchQueue.main.async { [weak self] in
            self?.parseNotification(data)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        let completion = pendingWriteCompletion
        pendingWriteCompletion = nil
        if let error {
            connectionState = .error(error.localizedDescription)
            return
        }
        completion?()
    }
}
