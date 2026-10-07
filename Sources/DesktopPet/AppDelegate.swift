import AppKit

// 把窗口、菜单栏、记账本、提醒器装配起来。真正的入口在 main.swift。

final class AppDelegate: NSObject, NSApplicationDelegate {

    /// ⚠️ 必须强引用。窗口是 `isReleasedWhenClosed = false` 的，但没有任何
    ///    其他对象持有它 —— 这里一松手，窗口就没了。
    private var petWindow: PetWindow?

    /// 同上，要拿它更新画面（进度、气泡、换图）。
    private var petView: PetView?

    /// 同上，StatusItem 内部持有 NSStatusItem，这个属性让它活到进程结束。
    private var statusItem: StatusItem?

    private let water = WaterStore()
    private let reminder = Reminder()

    private var isPaused = false

    // ⚠️ AppKit 的原点在**左下角**，y 值从下往上算。所以窗口变高不会影响
    //    落点高度（它往上长），只有 x 需要跟着宽度算。
    static let windowWidth: CGFloat = 200
    static let windowHeight: CGFloat = 300

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = makePetWindow()

        // ⚠️ 用 `orderFrontRegardless()`，**不要**用 `makeKeyAndOrderFront(_:)`。
        //
        // 后者会把窗口设成 key 并抢走焦点 —— 一个桌宠在启动时抢走你正在
        // 打字的那个窗口的焦点，是很讨厌的行为。
        // `orderFrontRegardless()` 只把窗口显示出来，不动焦点。
        window.orderFrontRegardless()
        petWindow = window

        // ---- 菜单栏
        let item = StatusItem()
        item.onTogglePause = { [weak self] in self?.togglePause() }
        item.onToggleQuietHours = { [weak self] in self?.toggleQuietHours() }
        item.onToggleVisible = { [weak self] in self?.toggleVisible() }
        item.onResetToday = { [weak self] in self?.resetToday() }
        item.onRecordOneCup = { [weak self] in self?.record(ml: 250) }
        statusItem = item

        // ---- 提醒
        reminder.onPrompt = { [weak self] in
            guard let self else { return }

            // 跨天检查挂在这里当"心跳"：每 20 分钟过一次。
            // 比为了半夜那一瞬间单开一个定时器简单得多，而且够用 ——
            // 真实场景里用户不会盯着菜单栏看它在 00:00 有没有归零。
            self.refreshUI()

            guard !self.isPaused else { return }
            self.petView?.showBubble("该喝水啦", seconds: 8)
        }
        reminder.start()

        loadCatImage()
        refreshUI()
    }

    // MARK: - 窗口

    private func makePetWindow() -> PetWindow {
        let width = AppDelegate.windowWidth
        let height = AppDelegate.windowHeight

        // 默认落在主屏右下角，离屏幕边缘留一点余地。
        let screenFrame = NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = NSPoint(
            x: screenFrame.maxX - width - 40,
            y: screenFrame.minY + 40
        )

        let window = PetWindow(
            contentRect: NSRect(origin: origin, size: NSSize(width: width, height: height)),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.applyPetAppearance()

        let view = PetView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        view.onRecordDrink = { [weak self] ml in self?.record(ml: ml) }
        window.contentView = view
        petView = view

        return window
    }

    // MARK: - 图片

    /// 三层降级的装配：
    ///   ① 主线程同步降采样 → 立刻显示"圆角照片卡片"（窗口不会是空的）
    ///   ② 后台跑 Vision 抠图（**绝不能在主线程同步跑**）
    ///   ③ 抠好了回主线程换图
    private func loadCatImage() {
        guard let source = CatCutout.loadSource() else {
            // 取不到图（`swift run` 跑裸二进制时必然如此）—— PetView 会退回
            // 画那个粉色小圆。不是错误，是设计好的第 ③ 层。
            return
        }
        petView?.sourceImage = NSImage(cgImage: source, size: .zero)

        // ⚠️ 首次 Vision 推理要几百毫秒到一两秒。在主线程同步跑的话窗口会
        //    白屏，而且**不报任何错** —— 看起来像应用卡死，方向全错。
        //
        // ⚠️ 这段跨队列捕获 self，在 **Swift 5 语言模式**下是合法的（最多
        //    一个 warning）。在 Swift 6 模式下会变成**编译错误** ——
        //    这正是 Package.swift 里那条"不要升 6.0"的现实理由。
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let cutout = CatCutout.cachedOrBuild(from: source) else {
                // 抠图失败就留在卡片形态（第 ② 层）。不写缓存，下次启动重试。
                return
            }
            DispatchQueue.main.async {
                // UI 一律只在主线程碰。
                self?.petView?.catImage = NSImage(cgImage: cutout, size: .zero)
            }
        }
    }

    // MARK: - 动作

    private func record(ml: Int) {
        let total = water.record(ml: ml)

        // 刚喝过就别马上再催 —— 下一次提醒从此刻起算。
        // （想要"不管喝没喝、每 20 分钟固定催一次"的话，删掉这一行即可。）
        reminder.noteDrank()

        petView?.showBubble("+\(ml) ml：\(total) / \(WaterStore.goalML)", seconds: 3)
        refreshUI()
    }

    private func resetToday() {
        water.resetToday()
        petView?.showBubble("今天重新开始", seconds: 3)
        refreshUI()
    }

    private func togglePause() {
        isPaused.toggle()
        refreshUI()
    }

    private func toggleQuietHours() {
        reminder.quietHoursEnabled.toggle()
        refreshUI()
    }

    private func toggleVisible() {
        guard let window = petWindow else { return }

        if window.isVisible {
            window.orderOut(nil)
        } else {
            // ⚠️ 还是 orderFrontRegardless —— 重新显示时也不该抢焦点。
            window.orderFrontRegardless()
        }

        refreshUI()
    }

    private func refreshUI() {
        // 顺手过一次跨天检查。已经在别处调过也无所谓，这个方法是幂等的。
        water.rolloverIfNeeded()

        let snapshot = water.snapshot

        petView?.render(
            todayML: snapshot.todayML,
            goalML: snapshot.goalML,
            stretchGoalML: snapshot.stretchGoalML
        )

        statusItem?.update(
            todayML: snapshot.todayML,
            goalML: snapshot.goalML,
            paused: isPaused,
            quietHours: reminder.quietHoursEnabled,
            petVisible: petWindow?.isVisible ?? false
        )
    }

    // MARK: - NSApplicationDelegate

    /// 关掉桌宠窗口不该把应用也结束掉（菜单栏图标还在）。
    /// 默认实现就是 false，这里写出来是为了让意图可见。
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// 让系统记住窗口状态这套东西闭嘴（对一个无边框小品应用没有意义）。
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}
