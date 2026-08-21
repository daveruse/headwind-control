//
//  HeadwindFanClient.swift
//  fan-toggle
//
//  Created by Dave Ruse on 8/20/26.
//

import CoreBluetooth
import Foundation

/// Minimal one-shot BLE client for the Control Center toggle's AppIntent.
///
/// The widget extension process is spun up fresh per intent invocation, so unlike
/// HeadwindBLEManager in the main app there's no persistent connection or UI state to
/// maintain — just connect, write the given commands in order, disconnect.
///
/// Protocol constants are duplicated from HeadwindBLEManager.swift in the main app
/// target — the two targets compile separately and can't share a Swift file directly.
/// All CoreBluetooth callbacks below run on the main queue (`CBCentralManager(delegate:queue:)`
/// is created with `queue: nil`), so access to this class's mutable state is effectively
/// serialized despite it not being actor-isolated.
final class HeadwindFanClient: NSObject, @unchecked Sendable {
    enum ClientError: LocalizedError {
        case bluetoothUnavailable
        case deviceNotFound
        case serviceNotFound
        case characteristicNotFound
        case timedOut

        var errorDescription: String? {
            switch self {
            case .bluetoothUnavailable: return "Bluetooth is unavailable."
            case .deviceNotFound: return "HEADWIND fan not found."
            case .serviceNotFound: return "HEADWIND service not found."
            case .characteristicNotFound: return "HEADWIND characteristic not found."
            case .timedOut: return "Timed out talking to the HEADWIND fan."
            }
        }
    }

    private static let serviceUUID = CBUUID(string: "A026EE0C-0A7D-4AB3-97FA-F1500F9FEB8B")
    private static let commandUUID = CBUUID(string: "A026E038-0A7D-4AB3-97FA-F1500F9FEB8B")
    private static let deviceNamePrefix = "HEADWIND"

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var commandCharacteristic: CBCharacteristic?
    private var pendingCommands: [[UInt8]] = []
    private var continuation: CheckedContinuation<Void, Error>?

    /// Connects to the fan, sends `commands` in order (waiting for each write to be
    /// confirmed), then disconnects. Bounded by a fixed timeout since this runs inside an
    /// AppIntent triggered from Control Center, which expects a prompt result.
    func send(_ commands: [[UInt8]]) async throws {
        pendingCommands = commands
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.continuation = continuation
            central = CBCentralManager(delegate: self, queue: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                self?.finish(with: ClientError.timedOut)
            }
        }
    }

    private func finish(with error: Error?) {
        guard let continuation else { return }
        self.continuation = nil
        if let peripheral, let central {
            central.cancelPeripheralConnection(peripheral)
        }
        central?.stopScan()
        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume()
        }
    }

    private func writeNextCommand() {
        guard let peripheral, let characteristic = commandCharacteristic else { return }
        guard !pendingCommands.isEmpty else {
            finish(with: nil)
            return
        }
        let bytes = pendingCommands.removeFirst()
        let writeType: CBCharacteristicWriteType =
            characteristic.properties.contains(.write) ? .withResponse : .withoutResponse
        peripheral.writeValue(Data(bytes), for: characteristic, type: writeType)
        if writeType == .withoutResponse {
            writeNextCommand()
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension HeadwindFanClient: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state == .poweredOn else {
            if central.state != .unknown && central.state != .resetting {
                finish(with: ClientError.bluetoothUnavailable)
            }
            return
        }

        if let savedID = HeadwindShared.defaults.string(forKey: HeadwindShared.peripheralIDKey).flatMap(UUID.init(uuidString:)),
           let known = central.retrievePeripherals(withIdentifiers: [savedID]).first {
            peripheral = known
            known.delegate = self
            central.connect(known, options: nil)
        } else {
            peripheral = nil
            central.scanForPeripherals(withServices: nil, options: nil)
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
        peripheral.delegate = self
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([Self.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        finish(with: error ?? ClientError.deviceNotFound)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if let error {
            finish(with: error)
        }
    }
}

// MARK: - CBPeripheralDelegate

extension HeadwindFanClient: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            finish(with: error)
            return
        }
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.serviceUUID }) else {
            finish(with: ClientError.serviceNotFound)
            return
        }
        peripheral.discoverCharacteristics([Self.commandUUID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            finish(with: error)
            return
        }
        guard let characteristic = service.characteristics?.first(where: { $0.uuid == Self.commandUUID }) else {
            finish(with: ClientError.characteristicNotFound)
            return
        }
        commandCharacteristic = characteristic
        HeadwindShared.defaults.set(peripheral.identifier.uuidString, forKey: HeadwindShared.peripheralIDKey)
        writeNextCommand()
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            finish(with: error)
            return
        }
        writeNextCommand()
    }
}
