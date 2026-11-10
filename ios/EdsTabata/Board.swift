import Foundation
import Combine
import CoreBluetooth
import UIKit

/// iPixel Color protocol (Briloner LED berichtenbord from Action, 64×16).
enum BoardProtocol {
    static let crcTable: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 { c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1) }
        return c
    }

    static func crc32(_ d: [UInt8]) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        for b in d { c = crcTable[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFFFFFF
    }

    static func le32(_ v: UInt32) -> [UInt8] {
        [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)]
    }

    static func command(_ cmd: UInt8, _ type: UInt8, _ payload: [UInt8] = []) -> [UInt8] {
        let n = 4 + payload.count
        return [UInt8(n & 0xFF), UInt8((n >> 8) & 0xFF), cmd, type] + payload
    }

    /// One still picture (PNG) in a single window, shown immediately, not saved.
    static func mediaPacket(_ png: [UInt8]) -> [UInt8] {
        let size = UInt32(png.count)
        let head: [UInt8] = [2, 0, 0] + le32(size) + le32(crc32(png)) + [0, 0]
        let total = head.count + png.count + 2
        return [UInt8(total & 0xFF), UInt8((total >> 8) & 0xFF)] + head + png
    }

    /// Media split into 12 KB windows (PNG = still, GIF = animation). Shown immediately, not saved.
    static func mediaPackets(_ data: [UInt8], gif: Bool) -> [[UInt8]] {
        let win = 12 * 1024
        let size = UInt32(data.count)
        let crc = crc32(data)
        var out: [[UInt8]] = []
        var off = 0
        while off < data.count {
            let end = min(data.count, off + win)
            let head: [UInt8] = [gif ? 3 : 2, 0, off == 0 ? 0 : 2] + le32(size) + le32(crc) + [gif ? 2 : 0, 0]
            let total = head.count + (end - off) + 2
            out.append([UInt8(total & 0xFF), UInt8((total >> 8) & 0xFF)] + head + Array(data[off..<end]))
            off = end
        }
        return out
    }

    /// Animated GIF of 64×16 frames; delays in 1/100 s. Plays once.
    static func gif(_ frames: [Frame], delays: [Int]) -> [UInt8]? {
        var map: [UInt32: UInt8] = [:]
        var pal: [UInt32] = []
        for f in frames {
            for i in stride(from: 0, to: f.px.count, by: 4) {
                let k = (UInt32(f.px[i]) << 16) | (UInt32(f.px[i + 1]) << 8) | UInt32(f.px[i + 2])
                if map[k] == nil {
                    if pal.count >= 256 { return nil }
                    map[k] = UInt8(pal.count)
                    pal.append(k)
                }
            }
        }
        var bits = 1
        while (1 << bits) < pal.count { bits += 1 }
        if bits < 2 { bits = 2 }
        while pal.count < (1 << bits) { pal.append(0) }
        var out: [UInt8] = Array("GIF89a".utf8)
        func u16(_ v: Int) { out.append(UInt8(v & 0xFF)); out.append(UInt8((v >> 8) & 0xFF)) }
        u16(Frame.w); u16(Frame.h)
        out += [UInt8(0xF0 | (bits - 1)), 0, 0]
        for c in pal { out += [UInt8((c >> 16) & 0xFF), UInt8((c >> 8) & 0xFF), UInt8(c & 0xFF)] }
        for (n, f) in frames.enumerated() {
            var ix = [UInt8](repeating: 0, count: Frame.w * Frame.h)
            for p in 0..<ix.count {
                let i = p * 4
                ix[p] = map[(UInt32(f.px[i]) << 16) | (UInt32(f.px[i + 1]) << 8) | UInt32(f.px[i + 2])] ?? 0
            }
            out += [0x21, 0xF9, 4, 0x04]; u16(delays[n]); out += [0, 0]
            out.append(0x2C); u16(0); u16(0); u16(Frame.w); u16(Frame.h); out.append(0)
            out.append(UInt8(bits))
            let d = lzw(ix, minCode: bits)
            var i = 0
            while i < d.count {
                let k = min(255, d.count - i)
                out.append(UInt8(k))
                out += d[i..<(i + k)]
                i += k
            }
            out.append(0)
        }
        out.append(0x3B)
        return out
    }

    private static func lzw(_ ix: [UInt8], minCode: Int) -> [UInt8] {
        let clear = 1 << minCode, eoi = clear + 1
        var size = minCode + 1, next = eoi + 1
        var dict: [Int: Int] = [:]
        var out: [UInt8] = []
        var buf = 0, cnt = 0
        func emit(_ c: Int) {
            buf |= c << cnt
            cnt += size
            while cnt >= 8 { out.append(UInt8(buf & 0xFF)); buf >>= 8; cnt -= 8 }
        }
        emit(clear)
        var cur = Int(ix[0])
        for i in 1..<ix.count {
            let k = Int(ix[i])
            let key = (cur << 8) | k
            if let f = dict[key] { cur = f; continue }
            emit(cur)
            if next == 4096 {
                emit(clear); dict = [:]; size = minCode + 1; next = eoi + 1
            } else {
                if next >= (1 << size) { size += 1 }
                dict[key] = next
                next += 1
            }
            cur = k
        }
        emit(cur)
        emit(eoi)
        if cnt > 0 { out.append(UInt8(buf & 0xFF)) }
        return out
    }

    static func png(_ f: Frame) -> [UInt8]? {
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let provider = CGDataProvider(data: Data(f.px) as CFData),
              let img = CGImage(width: Frame.w, height: Frame.h, bitsPerComponent: 8, bitsPerPixel: 32,
                                bytesPerRow: Frame.w * 4, space: cs,
                                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
              let data = UIImage(cgImage: img).pngData() else { return nil }
        return [UInt8](data)
    }
}

final class Board: NSObject, ObservableObject {
    @Published private(set) var status = "Niet verbonden"
    @Published private(set) var isConnected = false

    var brightness = 70
    var onConnect: (() -> Void)?

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var writeChar: CBCharacteristic?
    private var writeType: CBCharacteristicWriteType = .withoutResponse
    private var wantConnect = false
    private var scanToken = 0

    private let writeUUID = CBUUID(string: "FA02")
    private let notifyUUID = CBUUID(string: "FA03")

    // Serial send queue: commands first, then the newest picture (older pictures are skipped).
    private enum Media { case still(Frame), animation(() -> [UInt8]?) }
    private var commands: [[UInt8]] = []
    private var pendingMedia: Media?
    private var windows: [[UInt8]] = []
    private var mediaStart = Date()
    /// Average time to deliver an animation (s), used to start it on the right second.
    private(set) var uploadDelay: Double = 0.4
    private var chunks: [Data] = []
    private var chunkIdx = 0
    private var busy = false
    private var finishing = false
    private var awaitingAck = false
    private var jobToken = 0
    private var ackWait: Double = 1.5

    private var savedID: UUID? {
        get { UserDefaults.standard.string(forKey: "boardID").flatMap { UUID(uuidString: $0) } }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: "boardID") }
    }

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    // MARK: Public

    func connect() {
        wantConnect = true
        guard central.state == .poweredOn else { status = "Bluetooth staat uit"; return }
        if let p = peripheral, p.state == .connected || p.state == .connecting { return }
        if let id = savedID, let p = central.retrievePeripherals(withIdentifiers: [id]).first {
            attach(p)
            return
        }
        scan()
    }

    func disconnect() {
        wantConnect = false
        if let p = peripheral { central.cancelPeripheralConnection(p) }
        status = "Niet verbonden"
    }

    /// Forget the remembered board and look for a new one.
    func forgetAndSearch() {
        disconnect()
        savedID = nil
        peripheral = nil
        wantConnect = true
        if central.state == .poweredOn { scan() }
    }

    func show(_ f: Frame) {
        guard isConnected else { return }
        pendingMedia = .still(f)
        pump()
    }

    /// The board plays the animation itself (no flash every second). Built right before sending.
    func play(_ build: @escaping () -> [UInt8]?) {
        guard isConnected else { return }
        pendingMedia = .animation(build)
        pump()
    }

    func setPower(_ on: Bool) { send(BoardProtocol.command(0x07, 0x01, [on ? 1 : 0])) }
    func setBrightness(_ v: Int) { brightness = v; send(BoardProtocol.command(0x04, 0x80, [UInt8(max(1, min(100, v)))])) }
    func setRotation(_ r: Int) { send(BoardProtocol.command(0x06, 0x80, [UInt8(r & 3)])) }
    func syncTime() {
        let c = Calendar.current.dateComponents([.hour, .minute, .second], from: Date())
        send(BoardProtocol.command(0x01, 0x80, [UInt8(c.hour ?? 0), UInt8(c.minute ?? 0), UInt8(c.second ?? 0), 0]))
    }

    // MARK: Private

    private func scan() {
        status = "Zoeken…"
        central.scanForPeripherals(withServices: nil, options: nil)
        scanToken += 1
        let token = scanToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
            guard let self, token == self.scanToken, !self.isConnected else { return }
            self.central.stopScan()
            if self.peripheral == nil { self.status = "Bord niet gevonden" }
        }
    }

    private func attach(_ p: CBPeripheral) {
        peripheral = p
        p.delegate = self
        status = "Verbinden…"
        central.connect(p, options: nil)
    }

    private func send(_ bytes: [UInt8]) {
        guard isConnected else { return }
        commands.append(bytes)
        pump()
    }

    private func pump() {
        guard !busy, isConnected, let p = peripheral, writeChar != nil else { return }
        var bytes: [UInt8]
        var media = false
        var more = false
        if !windows.isEmpty {
            bytes = windows.removeFirst()
            media = true
            more = !windows.isEmpty
        } else if !commands.isEmpty {
            bytes = commands.removeFirst()
        } else if let m = pendingMedia {
            pendingMedia = nil
            var packets: [[UInt8]]
            switch m {
            case .still(let f):
                mediaStart = Date()
                guard let png = BoardProtocol.png(f) else { return }
                packets = BoardProtocol.mediaPackets(png, gif: false)
            case .animation(let build):
                mediaStart = Date()
                guard let g = build() else { return }
                packets = BoardProtocol.mediaPackets(g, gif: true)
            }
            guard !packets.isEmpty else { return }
            bytes = packets.removeFirst()
            windows = packets
            media = true
            more = !windows.isEmpty
        } else {
            return
        }
        let maxLen = max(20, min(p.maximumWriteValueLength(for: writeType), 244))
        chunks = stride(from: 0, to: bytes.count, by: maxLen).map { Data(bytes[$0..<min($0 + maxLen, bytes.count)]) }
        chunkIdx = 0
        busy = true
        finishing = false
        awaitingAck = media
        ackWait = more ? 8 : 1.5
        writeMore()
    }

    private func writeMore() {
        guard busy, !finishing, let p = peripheral, let ch = writeChar else { return }
        if chunkIdx >= chunks.count { finishJob(); return }
        if writeType == .withResponse {
            p.writeValue(chunks[chunkIdx], for: ch, type: .withResponse)
            chunkIdx += 1
            return
        }
        while chunkIdx < chunks.count && p.canSendWriteWithoutResponse {
            p.writeValue(chunks[chunkIdx], for: ch, type: .withoutResponse)
            chunkIdx += 1
        }
        if chunkIdx >= chunks.count { finishJob() }
    }

    private func finishJob() {
        finishing = true
        jobToken += 1
        let token = jobToken
        let wait: Double = awaitingAck ? ackWait : 0.05
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
            guard let self, token == self.jobToken else { return }
            self.jobDone()
        }
    }

    private func jobDone() {
        jobToken += 1
        if awaitingAck && windows.isEmpty {
            let t = Date().timeIntervalSince(mediaStart)
            if t < 5 { uploadDelay = uploadDelay * 0.5 + t * 0.5 }
        }
        busy = false
        finishing = false
        awaitingAck = false
        pump()
    }

    private func resetQueue() {
        busy = false
        finishing = false
        awaitingAck = false
        chunks = []
        commands = []
        windows = []
        jobToken += 1
    }
}

extension Board: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        if c.state == .poweredOn {
            if wantConnect || savedID != nil { connect() }
        } else {
            isConnected = false
            resetQueue()
            status = "Bluetooth staat uit"
        }
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral,
                        advertisementData ad: [String: Any], rssi: NSNumber) {
        let name = (ad[CBAdvertisementDataLocalNameKey] as? String) ?? p.name ?? ""
        guard name.uppercased().hasPrefix("LED_BLE") else { return }
        c.stopScan()
        scanToken += 1
        savedID = p.identifier
        attach(p)
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        status = "Verbinden…"
        p.discoverServices(nil)
    }

    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        isConnected = false
        status = "Verbinden mislukt"
    }

    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        isConnected = false
        writeChar = nil
        resetQueue()
        if wantConnect {
            status = "Opnieuw verbinden…"
            c.connect(p, options: nil)
        } else {
            status = "Niet verbonden"
        }
    }
}

extension Board: CBPeripheralDelegate {
    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        for s in p.services ?? [] { p.discoverCharacteristics([writeUUID, notifyUUID], for: s) }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        for ch in s.characteristics ?? [] {
            if ch.uuid == writeUUID {
                writeChar = ch
                writeType = ch.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
            }
            if ch.uuid == notifyUUID && ch.properties.contains(.notify) {
                p.setNotifyValue(true, for: ch)
            }
        }
        if writeChar != nil && !isConnected {
            isConnected = true
            status = "Verbonden"
            savedID = p.identifier
            resetQueue()
            syncTime()
            setPower(true)
            setBrightness(brightness)
            onConnect?()
        }
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        guard let v = ch.value else { return }
        let b = [UInt8](v)
        if b.count >= 5, b[0] == 5, b[1] == 0, awaitingAck, finishing { jobDone() }
    }

    func peripheralIsReady(toSendWriteWithoutResponse p: CBPeripheral) { writeMore() }

    func peripheral(_ p: CBPeripheral, didWriteValueFor ch: CBCharacteristic, error: Error?) { writeMore() }
}
