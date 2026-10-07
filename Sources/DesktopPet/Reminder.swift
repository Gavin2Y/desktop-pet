import AppKit

// 「每 20 分钟该喝水了」的节奏控制。
//
// ⚠️ 本文件的核心设计决策只有一条，但它决定了很多写法：
//
//    **不从 tick 计数推导时间，而是每次都拿墙上时钟重新比较
//      「现在 >= 下一次该提醒的时刻吗」。**
//
//    为什么不数 tick：`Timer` 在系统睡眠期间是不走的。如果逻辑是"每 20 分钟
//    tick 一次就提醒"，那么合上盖子睡一夜再打开，某些实现会一口气补发一串
//    通知。改成比较时间点之后，睡 8 小时醒来时那个条件只成立**恰好一次** ——
//    **只弹一条**，天然不会补发。用户手动改系统时间也一样自洽。
//
//    附带好处：tick 间隔是 20 秒还是 60 秒都不影响提醒的准时性，
//    只影响误差上限（最多晚一个 tick）。

final class Reminder {

    /// 提醒间隔。需求就是 20 分钟。
    static let interval: TimeInterval = 20 * 60

    /// 到点了要弹气泡。由 AppDelegate 接上 `PetView.showBubble`。
    var onPrompt: (() -> Void)?

    /// 夜间静音（22:00–08:00）。由菜单栏的开关控制。
    var quietHoursEnabled = true {
        didSet {
            // 立刻重算，否则开关拨完之后要等下一个 tick 才生效，
            // 看起来像"开关不灵"。
            wasQuiet = isQuietNow(Date())
        }
    }

    private var nextPromptAt: Date
    private var wasQuiet = false
    private var tickTimer: Timer?
    private var wakeObserver: NSObjectProtocol?

    private static let quietStartHour = 22
    private static let quietEndHour = 8

    init() {
        // 启动时**不要**立刻弹 —— 从"现在 + 20 分钟"起算。
        nextPromptAt = Date().addingTimeInterval(Self.interval)
    }

    deinit { stop() }

    // MARK: - 生命周期

    func start() {
        guard tickTimer == nil else { return }

        // ⚠️ 20 **秒**一跳，不是 20 分钟一跳。这个 timer 只负责"重新评估一下
        //    到点没到点"，不承载时间语义（见文件开头的说明）。
        let timer = Timer(timeInterval: 20, repeats: true) { [weak self] _ in
            self?.tick()
        }

        // ⚠️⚠️ **必须用 RunLoop.add(_:forMode: .common)，不能用 Timer.scheduledTimer。**
        //    后者只会把 timer 加进 .default 模式，而用户一拖窗口、一开菜单，
        //    主 run loop 就切到 eventTracking 模式，timer 直接停摆 ——
        //    症状是"开着菜单等，提醒永远不来"，非常难查。
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer

        // 唤醒后立刻重算一次，否则最坏要等一个 tick 才有反应。
        //
        // ⚠️ 必须注册到 `NSWorkspace.shared.notificationCenter`，
        //    **不是** `NotificationCenter.default`。用错了一辈子收不到，
        //    而且不报任何错。
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.tick()
        }
    }

    func stop() {
        tickTimer?.invalidate()
        tickTimer = nil
        if let token = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
            wakeObserver = nil
        }
    }

    // MARK: - 核心

    /// 重新评估"现在该不该提醒"。唤醒时、开关变化时、每个 tick 都会调它，
    /// 随时调用都是安全的。
    func tick(now: Date = Date()) {
        let quiet = isQuietNow(now)

        if quiet != wasQuiet {
            wasQuiet = quiet
            if !quiet {
                // 刚离开夜间时段（比如早上 08:00）：重起算 20 分钟。
                //
                // ⚠️ 不这么做的话，nextPromptAt 还停在昨晚 21:40，一过 08:00
                //    条件立刻成立 —— 用户会被 08:00 整弹一下。虽然只有一条
                //    （不是一堆），但体验上仍然突兀。
                nextPromptAt = now.addingTimeInterval(Self.interval)
            }
        }

        // 夜间：什么都不做，**也不推进** nextPromptAt。这样夜里积累的那段时间
        // 不会在早上集中爆发。
        if quiet { return }

        if now >= nextPromptAt {
            // 先推进再回调，防止回调里做的事（比如重绘）导致这一拍被重入。
            nextPromptAt = now.addingTimeInterval(Self.interval)
            onPrompt?()
        }
    }

    /// 用户记录了喝水 —— 下一次提醒从此刻起算。
    ///
    /// 理由：刚喝过还在催就是骚扰。如果你想要的是"不管喝没喝、每 20 分钟
    /// 固定催一次"，把 AppDelegate 里调用这个方法的那一行删掉即可。
    func noteDrank(now: Date = Date()) {
        nextPromptAt = now.addingTimeInterval(Self.interval)
    }

    /// 夜间时段（22:00–08:00）判定。
    ///
    /// ⚠️⚠️ 因为时段**跨午夜**，条件必须是 `h >= 22 || h < 8` 这种"或"。
    ///    写成 `22 <= h && h < 8` 是永远为假的经典错误 —— 症状是
    ///    "夜间静音看起来完全没生效"，而代码扫一眼还挺像那么回事。
    func isQuietNow(_ now: Date) -> Bool {
        guard quietHoursEnabled else { return false }
        let hour = Calendar.autoupdatingCurrent.component(.hour, from: now)
        return hour >= Self.quietStartHour || hour < Self.quietEndHour
    }
}
