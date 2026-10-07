import AppKit

// ⚠️ 未经编译验证 —— 见 README「未经编译验证」一节。
//
// 菜单栏图标。
//
// ⚠️ **这个不是可选功能。** Info.plist 里 `LSUIElement = true` 之后，应用
//    没有 Dock 图标，桌宠窗口又没有边框、没有任何关闭按钮 ——
//    **没有这个菜单栏项，应用就关不掉了**（只能去活动监视器杀进程）。

final class StatusItem {

    /// ⚠️ **必须存成属性（强引用）。**
    ///    `NSStatusBar.system.statusItem(withLength:)` 返回的对象**不会**被
    ///    系统或 AppKit 持有 —— 一旦这里不引用它，它立刻被释放，症状是
    ///    菜单栏图标「闪一下就没了」。
    private let item: NSStatusItem

    init() {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

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

        // ⚠️ **必须显式设 target。**
        //    不设的话，AppKit 会去响应链里找能响应这个 selector 的对象，
        //    找不到菜单项就是灰的、点了没反应。
        //    （退出之所以常常"碰巧能用"，只是因为 NSApplication 恰好在响应链上。）
        let quitItem = NSMenuItem(
            title: "退出桌面宠物",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = NSApp
        menu.addItem(quitItem)

        item.menu = menu
    }

    deinit {
        // 显式摘掉。不是必须的（进程退出时自然消失），但让意图清楚。
        NSStatusBar.system.removeStatusItem(item)
    }
}
