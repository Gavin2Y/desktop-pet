import AppKit

// 菜单栏图标 + 菜单。
//
// ⚠️ **这个不是可选功能。** Info.plist 里 `LSUIElement = true` 之后，应用
//    没有 Dock 图标，桌宠窗口又没有边框、没有任何关闭按钮 ——
//    **没有这个菜单栏项，应用就关不掉了**（只能去活动监视器杀进程）。
//
// ⚠️ 是 `NSObject` 的子类，不是普通的 final class。因为菜单项要靠
//    target/action 工作，而 target 必须是一个 ObjC 对象、action 必须是
//    ObjC 可见的方法（`@objc`）。`NSObject` 满足这两条。

final class StatusItem: NSObject {

    // MARK: - 回调（由 AppDelegate 接上）

    var onTogglePause: (() -> Void)?
    var onToggleQuietHours: (() -> Void)?
    var onToggleVisible: (() -> Void)?
    var onResetToday: (() -> Void)?
    var onRecordOneCup: (() -> Void)?

    // MARK: - 内部

    /// ⚠️ **必须存成属性（强引用）。**
    ///    `NSStatusBar.system.statusItem(withLength:)` 返回的对象**不会**被
    ///    系统或 AppKit 持有 —— 一旦这里不引用它，它立刻被释放，症状是
    ///    菜单栏图标「闪一下就没了」。
    private let item: NSStatusItem

    /// 这几项要在状态变化时改标题/勾选，所以得留着引用。
    private let progressItem = NSMenuItem()
    private let pauseItem = NSMenuItem()
    private let quietItem = NSMenuItem()
    private let visibleItem = NSMenuItem()

    override init() {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = item.button {
            // SF Symbols 里现成的脚印图标，不用自己准备图片资源。
            let image = NSImage(
                systemSymbolName: "pawprint.fill",
                accessibilityDescription: "桌面宠物"
            )
            // isTemplate = true 让它跟随菜单栏明暗自动变色。
            image?.isTemplate = true
            button.image = image
            button.toolTip = "桌面宠物"
        }

        let menu = NSMenu()

        // ---- 纯展示行。disabled 的菜单项是灰的，但仍然可读。
        progressItem.title = "今日 — / — ml"
        progressItem.isEnabled = false
        menu.addItem(progressItem)

        menu.addItem(.separator())

        configure(pauseItem, title: "暂停提醒", action: #selector(didTapPause))
        menu.addItem(pauseItem)

        configure(quietItem, title: "夜间静音（22:00–08:00）", action: #selector(didTapQuiet))
        menu.addItem(quietItem)

        // 这两项不需要保留引用（不改标题也不改勾选）。
        menu.addItem(makeItem(title: "记录一杯 250 ml", action: #selector(didTapOneCup)))
        menu.addItem(makeItem(title: "重置今天", action: #selector(didTapReset)))

        configure(visibleItem, title: "显示桌宠", action: #selector(didTapVisible))
        menu.addItem(visibleItem)

        menu.addItem(.separator())

        // ⚠️ **退出这一项保持原样：target = NSApp。**
        //    「退出」之所以常常"碰巧能用"，是因为 NSApplication 恰好在响应
        //    链上、能响应 terminate:。别的项没有这种运气，必须显式设 target。
        let quitItem = NSMenuItem(
            title: "退出桌面宠物",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = NSApp
        menu.addItem(quitItem)

        item.menu = menu
    }

    // MARK: - 状态刷新

    /// 由 AppDelegate 在状态变化后**主动调用**。
    ///
    /// ⚠️ 不要改成依赖 `NSMenuDelegate.menuNeedsUpdate`：那个回调的时机由
    ///    AppKit 内部决定，而且 `NSMenu.delegate` 是 **weak** 引用 —— 多一个
    ///    能踩的坑，换不来任何好处。主动调用是确定性的。
    func update(
        todayML: Int,
        goalML: Int,
        paused: Bool,
        quietHours: Bool,
        petVisible: Bool
    ) {
        progressItem.title = "今日 \(todayML) / \(goalML) ml"
        pauseItem.state = paused ? .on : .off
        quietItem.state = quietHours ? .on : .off
        visibleItem.state = petVisible ? .on : .off
    }

    // MARK: - 菜单项构造

    private func makeItem(title: String, action: Selector) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: "")
        // ⚠️ **必须显式设 target。**
        //    不设的话，AppKit 会去响应链里找能响应这个 selector 的对象，
        //    找不到菜单项就是灰的、点了没反应。
        menuItem.target = self
        return menuItem
    }

    /// 给 init 里那三个预先建好的项补上标题和 action。
    private func configure(_ menuItem: NSMenuItem, title: String, action: Selector) {
        menuItem.title = title
        menuItem.action = action
        menuItem.target = self
    }

    // MARK: - Action
    //
    // ⚠️ `@objc` 不能省 —— `#selector` 只认 ObjC 可见的方法。

    @objc private func didTapPause() { onTogglePause?() }
    @objc private func didTapQuiet() { onToggleQuietHours?() }
    @objc private func didTapVisible() { onToggleVisible?() }
    @objc private func didTapReset() { onResetToday?() }
    @objc private func didTapOneCup() { onRecordOneCup?() }

    deinit {
        // 显式摘掉。不是必须的（进程退出时自然消失），但让意图清楚。
        NSStatusBar.system.removeStatusItem(item)
    }
}
