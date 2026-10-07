import AppKit

// ⚠️ 未经编译验证 —— 见 README「未经编译验证」一节。
//
// 宠物本体：一个会上下浮动的小人。
//
// 为什么是纯 AppKit 画、而不是 SwiftUI：
// 透明无边框窗口 + NSHostingView（SwiftUI 嵌 AppKit）是这套组合里最容易
// 翻车的部分，有记录的坑包括 NSHostingView 会自己画一层不透明背景盖住透明
// 窗口、拿掉 .titled 后命中测试坏掉、macOS 15 上「窗口显示但收不到鼠标事件」。
// 而本仓库**没有 macOS 环境可以编译调试**，所以选一次性绕开这些坑的写法。
//
// 另外这里**不引入任何图片资源** —— 全部用 NSBezierPath 现画。少一份要打包、
// 要签名、可能在运行时找不到的文件。

final class PetView: NSView {

    /// 上下浮动的偏移量（点）。由定时器驱动。
    private var bobOffset: CGFloat = 0

    /// 相位。用 sin 让它平滑地来回，而不是线性往返。
    private var phase: CGFloat = 0

    private var animationTimer: Timer?

    /// 每秒重绘次数。30 对一个小圆点来说绰绰有余，也不用担心耗电。
    private static let framesPerSecond: Double = 30

    // MARK: - 生命周期

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if window == nil {
            stopAnimating()
        } else {
            startAnimating()
        }
    }

    private func startAnimating() {
        guard animationTimer == nil else { return }

        // ⚠️ block 里用 [weak self]，否则 Timer 强引用 block、block 强引用
        //    self，形成环，视图永远不会被释放。
        animationTimer = Timer.scheduledTimer(
            withTimeInterval: 1.0 / PetView.framesPerSecond,
            repeats: true
        ) { [weak self] _ in
            guard let self else { return }
            self.phase += 0.05
            self.bobOffset = sin(self.phase) * 6
            // 视图不会自动知道要重画，必须显式标记脏。
            self.needsDisplay = true
        }
    }

    private func stopAnimating() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    deinit {
        // invalidate 必须发生在 deinit 里能安全碰到的最后时刻。
        // Timer 会在下一次触发时因为 weak self 为 nil 而自行退场，
        // 这里只是尽早收摊。
        animationTimer?.invalidate()
    }

    // MARK: - 绘制

    override func draw(_ dirtyRect: NSRect) {
        // ⚠️ 这里**刻意不填充背景**。
        //    窗口是透明的（isOpaque = false + backgroundColor = .clear），
        //    没画到的地方就保持透明。若在这里填一层背景色，窗口就变成方块了。

        let side = min(bounds.width, bounds.height)
        guard side > 0 else { return }

        let bodyDiameter = side * 0.62
        let bodyRect = NSRect(
            x: bounds.midX - bodyDiameter / 2,
            y: bounds.midY - bodyDiameter / 2 + bobOffset,
            width: bodyDiameter,
            height: bodyDiameter
        )

        // 身体
        NSColor.systemPink.setFill()
        NSBezierPath(ovalIn: bodyRect).fill()

        // 两只眼睛
        let eyeDiameter = bodyDiameter * 0.16
        let eyeCenterX = bodyDiameter * 0.17
        let eyeCenterY = bodyRect.midY + bodyDiameter * 0.10

        NSColor.black.setFill()
        for direction in [CGFloat(-1), CGFloat(1)] {
            let eyeRect = NSRect(
                x: bodyRect.midX + direction * eyeCenterX - eyeDiameter / 2,
                y: eyeCenterY - eyeDiameter / 2,
                width: eyeDiameter,
                height: eyeDiameter
            )
            NSBezierPath(ovalIn: eyeRect).fill()
        }
    }
}
