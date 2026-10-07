import AppKit

// ⚠️ 未经编译验证 —— 见 README「未经编译验证」一节。
//
// 把窗口和菜单栏图标装配起来。真正的入口在 main.swift。

final class AppDelegate: NSObject, NSApplicationDelegate {

    /// ⚠️ 必须强引用。窗口是 `isReleasedWhenClosed = false` 的，但没有任何
    ///    其他对象持有它 —— 这里一松手，窗口就没了。
    private var petWindow: PetWindow?

    /// 同上，StatusItem 内部持有 NSStatusItem，这个属性让它活到进程结束。
    private var statusItem: StatusItem?

    /// 桌宠的边长。窗口是正方形，内容自己按短边计算。
    private static let petSize: CGFloat = 160

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = makePetWindow()
        // ⚠️ 用 `orderFrontRegardless()`，**不要**用 `makeKeyAndOrderFront(_:)`。
        //
        // 后者会把窗口设成 key 并抢走焦点 —— 一个桌宠在启动时抢走你正在
        // 打字的那个窗口的焦点，是很讨厌的行为。
        // `orderFrontRegardless()` 只把窗口显示出来，不动焦点。
        window.orderFrontRegardless()

        petWindow = window

        // 菜单栏图标 —— 见 StatusItem.swift 里「这不是可选功能」那段。
        statusItem = StatusItem()
    }

    private func makePetWindow() -> PetWindow {
        let side = AppDelegate.petSize

        // 默认落在主屏右下角，离屏幕边缘留一点余地。
        let screenFrame = NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = NSPoint(
            x: screenFrame.maxX - side - 40,
            y: screenFrame.minY + 40
        )

        let window = PetWindow(
            contentRect: NSRect(origin: origin, size: NSSize(width: side, height: side)),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.applyPetAppearance()
        window.contentView = PetView(frame: NSRect(x: 0, y: 0, width: side, height: side))

        return window
    }

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
