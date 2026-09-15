import Foundation

struct Reminder: Codable, Equatable {
    var mode = "idle"
    var dueAt: Double? = nil
    var remainingMs: Double = 45 * 60_000
    var token = UUID().uuidString
}
struct Preferences: Codable {
    var name = "兔兔"
    var interval = 45
    var notifications = false
}
struct Drink: Codable {
    var id: String
    var ts: Double
    var day: String
    var timerBefore: Reminder?
}
struct WaterState: Codable {
    var version = 1
    var settings = Preferences()
    var records: [Drink] = []
    var timer = Reminder()
    static func day(_ now: Double) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = .current; f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date(timeIntervalSince1970: now / 1000))
    }
    func remaining(_ now: Double) -> Double {
        if timer.mode == "running" { return max(0, (timer.dueAt ?? now) - now) }
        return timer.mode == "due" ? 0 : timer.remainingMs
    }
    @discardableResult
    mutating func apply(_ action: String, args: [String: Any] = [:], now: Double = Date().timeIntervalSince1970 * 1000) throws -> String? {
        switch action {
        case "start":
            if timer.mode == "running" || timer.mode == "due" { return nil }
            let ms = timer.mode == "paused" ? timer.remainingMs : Double(settings.interval) * 60_000
            timer = Reminder(mode: "running", dueAt: now + ms, remainingMs: ms)
        case "pause":
            if timer.mode == "running" || timer.mode == "due" { timer = Reminder(mode: "paused", remainingMs: remaining(now)) }
        case "snooze":
            guard timer.mode == "running" || timer.mode == "due" else { throw StateError.message("开始陪伴后，才可以稍后提醒。") }
            timer = Reminder(mode: "running", dueAt: now + 600_000, remainingMs: 600_000)
        case "record":
            let id = UUID().uuidString, before = timer
            let active = timer.mode == "running" || timer.mode == "due", ms = Double(settings.interval) * 60_000
            timer = Reminder(mode: active ? "running" : timer.mode, dueAt: active ? now + ms : nil, remainingMs: ms, token: id)
            records.append(Drink(id: id, ts: now, day: Self.day(now), timerBefore: before)); return id
        case "undo":
            guard let id = args["recordId"] as? String, let item = records.first(where: {$0.id == id}) else { throw StateError.message("这条记录已经撤销了。") }
            if timer.token == id, let before = item.timerBefore { timer = before }
            records.removeAll(where: {$0.id == id})
        case "configure":
            guard let value = args["interval"] as? NSNumber, value.doubleValue.rounded() == value.doubleValue, (1...240).contains(value.intValue) else { throw StateError.message("请填写 1–240 之间的整数分钟。") }
            let name = (args["name"] as? String ?? "兔兔").trimmingCharacters(in: .whitespacesAndNewlines)
            settings.name = name.isEmpty ? "兔兔" : String(name.prefix(12)); settings.interval = value.intValue
            let active = timer.mode == "running" || timer.mode == "due", ms = Double(settings.interval) * 60_000
            timer = Reminder(mode: active ? "running" : timer.mode, dueAt: active ? now + ms : nil, remainingMs: ms)
        default: throw StateError.message("不支持这个操作。")
        }
        return nil
    }
    mutating func advance(_ now: Double = Date().timeIntervalSince1970 * 1000) -> Bool {
        guard timer.mode == "running", let due = timer.dueAt, due <= now else { return false }
        timer.mode = "due"; timer.remainingMs = 0; return true
    }
}
enum StateError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
final class StateStore {
    let url: URL
    var state = WaterState()
    var storageError: String?
    init(directory: URL) {
        url = directory.appendingPathComponent("water-state.json")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: url.path) {
                let data = try Data(contentsOf: url)
                do { state = try JSONDecoder().decode(WaterState.self, from: data) }
                catch {
                    try data.write(to: directory.appendingPathComponent("water-state-backup-\(Int(Date().timeIntervalSince1970)).json"), options: .atomic)
                    storageError = "旧记录无法读取，已保留备份。"
                }
            }
        } catch { storageError = "记录暂时无法保存：\(error.localizedDescription)" }
    }
    func save() {
        do { let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; try encoder.encode(state).write(to: url, options: .atomic); storageError = nil }
        catch { storageError = "记录暂时无法保存，请保持应用开启。" }
    }
}
