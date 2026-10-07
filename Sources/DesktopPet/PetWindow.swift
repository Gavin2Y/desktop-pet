import AppKit

// ⚠️ 未经编译验证 —— 见 README「未经编译验证」一节。
//
// 桌宠的窗口：透明、无边框、置顶、可以拖着走。

final class PetWindow: NSWindow {

    // MARK: - 为什么需要一个 NSWindow 子类

    // 因为 **borderless 窗口默认 `canBecomeKey == false`**。
    //
    // 这个默认值会导致 `makeKeyAndOrderFront(_:)` **静默失败** —— 不报错、
    // 不崩溃，只在控制台打一行
    //     returned NO from -[NSWindow canBecomeKeyWindow]
    // 症状是"代码看起来完全正确，但窗口就是不出现"，极难排查。
    //
    // 我们干脆覆写成 true：既让窗口能正常显示，也让它能成为 key window
    // 从而收到鼠标事件（拖拽要用）。
    override var canBecomeKey: Bool { true }

    // 但我们**不想**抢 main window 的位置 —— 一个桌宠不该影响别的应用的
    // 主窗口关系。所以这个保持 false。
    override var canBecomeMain: Bool { false }

    // MARK: - 拖拽

    private var grabOffsetInWindow: NSPoint?
    private var windowOriginAtGrab: NSPoint?

    /// 这块矩形（**窗口坐标**）里的左键按下**不**触发拖拽，事件会继续往下传给
    /// 子视图。
    ///
    /// 存在的理由：下面的 `sendEvent(_:)` 会吞掉所有左键事件来实现拖拽，于是
    /// 同一个窗口里的 `NSButton` **永远收不到点击**。让控件所占的那块区域豁免即可。
    ///
    /// ⚠️ 默认 `.zero`。`NSRect.zero.isEmpty == true`，所以下面那个判断自动变成
    ///    "没有排除区"，行为**完全退回加这个属性之前** —— 也就是说单独加上这个
    ///    属性是零风险的，可以独立验证。
    ///
    /// 由 `PetView.syncDragExclusionRect()` 负责写入（它知道控件实际占了哪一块）。
    var dragExclusionRect: NSRect = .zero

    /// 一次性把窗口的外观属性摆好。由 AppDelegate 在创建后立刻调用。
    func applyPetAppearance() {
        // 透明三件套。缺任何一个，窗口就是个灰底方块。
        isOpaque = false
        backgroundColor = .clear

        // ⚠️ 关掉阴影。开着的话，SwiftUI/重绘内容一移动就会在桌面上留下
        //    阴影残影（需要额外调 invalidateShadow() 才能清）。
        //    桌宠这类不断重绘的窗口直接关掉最省事。
        hasShadow = false

        // 浮在普通窗口之上。想更霸道可以换 .screenSaver，但那个会盖住
        // 系统的一些 UI，对一个桌宠来说过分了。
        level = .floating

        // 在所有 Space 上都出现，跟着切换走，并且不进 Cmd+Tab 循环。
        //
        // ⚠️ 已知限制：**别人进入全屏应用时本窗口仍可能看不见**，
        //    即使带了 .fullScreenAuxiliary。这是 Apple 论坛上反复出现的
        //    抱怨，没有可靠解法 —— 别把"能浮在全屏应用之上"当需求。
        collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .fullScreenAuxiliary,
            .ignoresCycle,
        ]

        // 点击不激活本应用（桌宠不该抢焦点）。
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }

    // MARK: - 为什么要自己实现拖拽

    // 按理说 `isMovableByWindowBackground = true` 就能拖，但**对 borderless
    // 窗口基本不生效**：Apple 文档明说 `isMovable` 为 false 时它被忽略，
    // 而且 borderless 窗口没有 title bar 那套负责拖拽的 frame view。
    //
    // 所以在 sendEvent 这一层自己算位移。这是 borderless 窗口的常规做法。
    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            let point = event.locationInWindow

            // ⚠️ 坐标系：`event.locationInWindow` 是**窗口坐标**，所以
            //    `dragExclusionRect` 也必须是窗口坐标。borderless 窗口里
            //    contentView.frame 恰好等于 (0, 0, w, h)，视图坐标和窗口坐标
            //    数值相同 —— 但**别依赖这个巧合**，PetView 那边用
            //    `convert(_:to: nil)` 显式换算过来。
            if !dragExclusionRect.isEmpty && dragExclusionRect.contains(point) {
                // 显式清空，防止上一次拖拽的残留值让下面的 dragged 分支误触发。
                grabOffsetInWindow = nil
                windowOriginAtGrab = nil

                // ⚠️⚠️ **必须是 break，不能是 return。**
                //    break 跳出 switch 后会落到末尾的 super.sendEvent(event)，
                //    事件才到得了按钮。写成 return 的话事件在这里就没了，
                //    症状是"按钮完全没反应" —— 看起来像按钮本身的问题，极难查。
                break
            }

            grabOffsetInWindow = point
            windowOriginAtGrab = frame.origin

        case .leftMouseDragged:
            if let grab = grabOffsetInWindow, let origin = windowOriginAtGrab {
                let now = event.locationInWindow
                setFrameOrigin(NSPoint(
                    x: origin.x + (now.x - grab.x),
                    y: origin.y + (now.y - grab.y)
                ))
                // ⚠️ 处理完直接 return，**不要把事件继续往下传**。
                //    传下去的话视图层还会把它当成一次点击/手势处理。
                return
            }

        case .leftMouseUp:
            grabOffsetInWindow = nil
            windowOriginAtGrab = nil

        default:
            break
        }

        super.sendEvent(event)
    }
}
