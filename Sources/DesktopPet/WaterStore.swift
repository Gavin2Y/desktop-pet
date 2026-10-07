import Foundation

// 今日饮水量的记账本。
//
// 职责边界：**只管数字和日期**。它不知道窗口、不知道定时器、不发通知 ——
// 那些分别属于 AppDelegate / Reminder / PetView。这样它能被单独读懂。

final class WaterStore {

    /// 给 UI 用的一份快照。UI 不需要看见存储细节，更不该自己去读 UserDefaults。
    struct Snapshot {
        let todayML: Int
        let goalML: Int
        let stretchGoalML: Int
    }

    /// 每天**至少**要喝到的量。
    static let goalML = 2000

    /// 力求达到的量。不是硬指标 —— 进度条越过 goal 之后继续朝它长。
    static let stretchGoalML = 2800

    private enum Key {
        /// 存当天 00:00 的 Date。
        static let day = "water.day"
        /// 存当天的累计毫升数。
        static let ml = "water.ml"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // 启动时就过一遍跨天检查：昨天的数字不该被当成今天的。
        rolloverIfNeeded()
    }

    var snapshot: Snapshot {
        Snapshot(
            todayML: defaults.integer(forKey: Key.ml),
            goalML: Self.goalML,
            stretchGoalML: Self.stretchGoalML
        )
    }

    /// 记一杯。返回记完之后的总量，方便调用方直接拿去显示。
    @discardableResult
    func record(ml: Int) -> Int {
        rolloverIfNeeded()
        let next = defaults.integer(forKey: Key.ml) + ml
        defaults.set(next, forKey: Key.ml)
        return next
    }

    func resetToday() {
        defaults.set(0, forKey: Key.ml)
        defaults.set(Self.today(), forKey: Key.day)
    }

    /// 跨天自动重置。
    ///
    /// ⚠️ 用 `Calendar.autoupdatingCurrent`，**不是** `Calendar.current`。
    ///    后者是"创建那一刻"的快照，用户之后改时区、跨夏令时它都不知道。
    ///    桌宠是要在后台连着挂好几天的，这不是理论问题。
    ///
    /// ⚠️ 判定"是不是同一天"用 `isDate(_:inSameDayAs:)`，**不要**直接比 Date 相等。
    ///    存进去的是 startOfDay，任何精度上的一点点不一致都会变成"每天重置两次"
    ///    或者"永远不重置" —— 而这两种症状都很难从表象反推回这一行。
    func rolloverIfNeeded() {
        let today = Self.today()
        if let stored = defaults.object(forKey: Key.day) as? Date,
           Self.calendar.isDate(stored, inSameDayAs: today) {
            return
        }
        defaults.set(today, forKey: Key.day)
        defaults.set(0, forKey: Key.ml)
    }

    private static var calendar: Calendar { Calendar.autoupdatingCurrent }

    private static func today() -> Date {
        calendar.startOfDay(for: Date())
    }
}
