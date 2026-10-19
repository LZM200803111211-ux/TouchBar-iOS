import Foundation
import CoreBluetooth

/// 双向 BLE：iPhone 当外设。
///   cmd   iPhone -> Windows   （点按键时发）
///   stat  Windows -> iPhone   （电脑主动推播放信息 / CPU 占用）
final class BLE: NSObject, ObservableObject, CBPeripheralManagerDelegate {

    static let svcUUID  = CBUUID(string: "8E1A0001-7D3B-4F2A-9C61-0A2B3C4D5E6F")
    static let cmdUUID  = CBUUID(string: "8E1A0002-7D3B-4F2A-9C61-0A2B3C4D5E6F")
    static let statUUID = CBUUID(string: "8E1A0003-7D3B-4F2A-9C61-0A2B3C4D5E6F")

    private var manager: CBPeripheralManager?
    private var cmdChar: CBMutableCharacteristic?
    private var statChar: CBMutableCharacteristic?

    @Published var connected = false
    @Published var lastSent = ""

    // 电脑推过来的状态
    @Published var title = ""
    @Published var artist = ""
    @Published var playing = false
    @Published var cpu: Double = 0
    @Published var gpu: Double = 0
    @Published var ram: Double = 0
    @Published var ramText = ""
    @Published var cover = ""

    func start() {
        guard manager == nil else { return }
        manager = CBPeripheralManager(delegate: self, queue: nil)
    }

    func peripheralManagerDidUpdateState(_ p: CBPeripheralManager) {
        guard p.state == .poweredOn else { return }
        let cmd = CBMutableCharacteristic(
            type: BLE.cmdUUID,
            properties: [.notify, .read],
            value: nil, permissions: [.readable])
        let stat = CBMutableCharacteristic(
            type: BLE.statUUID,
            properties: [.write, .writeWithoutResponse],
            value: nil, permissions: [.writeable])
        cmdChar = cmd
        statChar = stat
        let svc = CBMutableService(type: BLE.svcUUID, primary: true)
        svc.characteristics = [cmd, stat]
        p.removeAllServices()
        p.add(svc)
    }

    func peripheralManager(_ p: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        p.startAdvertising([
            CBAdvertisementDataLocalNameKey: "iPhoneTouchBar",
            CBAdvertisementDataServiceUUIDsKey: [BLE.svcUUID]
        ])
    }

    func peripheralManager(_ p: CBPeripheralManager, central: CBCentral,
                           didSubscribeTo ch: CBCharacteristic) { connected = true }
    func peripheralManager(_ p: CBPeripheralManager, central: CBCentral,
                           didUnsubscribeFrom ch: CBCharacteristic) { connected = false }
    func peripheralManagerIsReady(toUpdateSubscribers p: CBPeripheralManager) {}

    /// 收到电脑写过来的 JSON
    func peripheralManager(_ p: CBPeripheralManager,
                           didReceiveWrite requests: [CBATTRequest]) {
        for r in requests {
            guard r.characteristic.uuid == BLE.statUUID, let d = r.value else { continue }
            apply(d)
            p.respond(to: r, withResult: .success)
        }
    }

    private func apply(_ data: Data) {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        DispatchQueue.main.async {
            if let t = obj["title"] as? String { self.title = t }
            if let a = obj["artist"] as? String { self.artist = a }
            if let p = obj["playing"] as? Bool { self.playing = p }
            if let c = obj["cpu"] as? Double { self.cpu = c }
            if let g = obj["gpu"] as? Double { self.gpu = g }
            if let r = obj["ram"] as? Double { self.ram = r }
            if let rt = obj["ramText"] as? String { self.ramText = rt }
            if let c = obj["cover"] as? String { self.cover = c }
        }
    }

    func send(_ cmd: String) {
        guard let ch = cmdChar, let m = manager else { return }
        lastSent = cmd
        m.updateValue(Data(cmd.utf8), for: ch, onSubscribedCentrals: nil)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
