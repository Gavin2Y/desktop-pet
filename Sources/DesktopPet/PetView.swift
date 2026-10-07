import AppKit

// 宠物本体 + 它下面那一整套控件（气泡 / 进度 / 三个记一杯的按钮）。
//
// 为什么是纯 AppKit 画、而不是 SwiftUI：
// 透明无边框窗口 + NSHostingView（SwiftUI 嵌 AppKit）是这套组合里最容易
// 翻车的部分，有记录的坑包括 NSHostingView 会自己画一层不透明背景盖住透明
// 窗口、拿掉 .titled 后命中测试坏掉、macOS 15 上「窗口显示但收不到鼠标事件」。
// 而本仓库**没有 macOS 环境可以编译调试**，所以选一次性绕开这些坑的写法。

final class PetView: NSView {

    // MARK: - 对外接口

    /// 点了「200 / 250 / 300」其中一个按钮。参数是毫升数。
    var onRecordDrink: ((Int) -> Void)?

    /// 抠好的猫（带 alpha）。为 nil 时走降级外观。
    var catImage: NSImage? {
        didSet { needsDisplay = true }
    }

    /// 降采样后的原照片。抠图还没跑完（或者失败了）时用它画"圆角照片卡片"。
    var sourceImage: NSImage? {
        didSet { needsDisplay = true }
    }

    /// 刷新今日进度。由 AppDelegate 在记账/重置/跨天后调用。
    func render(todayML: Int, goalML: Int, stretchGoalML: Int) {
        self.todayML = todayML
        self.goalML = goalML
        self.stretchGoalML = stretchGoalML
        needsDisplay = true
    }

    /// 冒一句话，`seconds` 秒后自动消失。
    func showBubble(_ text: String, seconds: TimeInterval) {
        bubbleText = text
        bubbleHideAt = Date().addingTimeInterval(seconds)
        needsDisplay = true
    }

    // MARK: - 状态

    private var todayML = 0
    private var goalML = WaterStore.goalML
    private var stretchGoalML = WaterStore.stretchGoalML

    private var bubbleText: String?
    private var bubbleHideAt: Date?

    private var bobOffset: CGFloat = 0
    private var phase: CGFloat = 0
    private var animationTimer: Timer?
    private var doseButtons: [NSButton] = []

    /// 每秒重绘次数。30 对一只小桌宠来说绰绰有余，也不用担心耗电。
    private static let framesPerSecond: Double = 30

    /// 控件区（从窗口底边往上算）的高度。
    ///
    /// ⚠️ 这个常量和 `PetWindow.dragExclusionRect` **必须对得上** ——
    ///    它决定"从多高往下算是不拖窗口、而是点控件"。改布局时两边一起改。
    static let controlsHeight: CGFloat = 90

    // MARK: - 布局

    /// 猫的那块方框。从窗口顶边往下量 208 pt（气泡占掉上面那一条）。
    private var catRect: NSRect {
        NSRect(x: 20, y: bounds.height - 208, width: bounds.width - 40, height: 160)
    }

    private static func progressBarRect(within bounds: NSRect) -> NSRect {
        NSRect(x: 20, y: 58, width: bounds.width - 40, height: 8)
    }

    // MARK: - 生命周期

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setUpButtons()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUpButtons()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if window == nil {
            stopAnimating()
        } else {
            startAnimating()
            syncDragExclusionRect()
        }
    }

    override func layout() {
        super.layout()
        layoutControls()
        syncDragExclusionRect()
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        layoutControls()
        syncDragExclusionRect()
    }

    // MARK: - 按钮

    private func setUpButtons() {
        for dose in [200, 250, 300] {
            let button = makeDoseButton(ml: dose)
            addSubview(button)
            doseButtons.append(button)
        }
        layoutControls()
    }

    private func makeDoseButton(ml: Int) -> NSButton {
        let button = NSButton(
            title: "\(ml)",
            target: self,
            action: #selector(doseTapped(_:))
        )

        // ⚠️⚠️ **必须用一个会画底衬的 bezel style。**
        //    透明无边框窗口的**透明区域，点击会直接穿透到桌面**
        //    （WindowServer 逐像素命中测试）。用了不画背景的按钮样式，
        //    按钮那块就是"透明"的 —— 症状是"按钮点不动，但代码看起来
        //    完全正确"，而且会让人去查 action/target，方向全错。
        button.bezelStyle = .rounded
        button.setButtonType(.momentaryPushIn)
        button.font = NSFont.systemFont(ofSize: 12, weight: .medium)

        // 用 tag 携带毫升数，省掉三个只差一个数字的 @objc 方法。
        button.tag = ml
        button.toolTip = "记录喝了 \(ml) ml"

        return button
    }

    private func layoutControls() {
        let count = CGFloat(doseButtons.count)
        guard count > 0 else { return }

        let buttonWidth: CGFloat = 58
        let buttonHeight: CGFloat = 30
        let buttonY: CGFloat = 20
        let gap = (bounds.width - buttonWidth * count) / (count + 1)

        for (index, button) in doseButtons.enumerated() {
            button.frame = NSRect(
                x: gap + (buttonWidth + gap) * CGFloat(index),
                y: buttonY,
                width: buttonWidth,
                height: buttonHeight
            )
        }
    }

    @objc private func doseTapped(_ sender: NSButton) {
        onRecordDrink?(sender.tag)
    }

    /// 把"控件占了哪一块"告诉窗口，让 `PetWindow.sendEvent` 在那块区域里
    /// 不要触发拖拽（否则按钮永远收不到点击）。
    private func syncDragExclusionRect() {
        // ⚠️ 必须换算成**窗口坐标** —— `PetWindow.sendEvent` 里比的是
        //    `event.locationInWindow`。borderless 窗口里 contentView.frame
        //    恰好是 (0,0,w,h)，两者数值相同，但别依赖这个巧合。
        let rect = NSRect(x: 0, y: 0, width: bounds.width, height: Self.controlsHeight)
        (window as? PetWindow)?.dragExclusionRect = convert(rect, to: nil)
    }

    // MARK: - 动画

    private func startAnimating() {
        guard animationTimer == nil else { return }

        let timer = Timer(
            timeInterval: 1.0 / PetView.framesPerSecond,
            repeats: true
        ) { [weak self] _ in
            guard let self else { return }

            self.phase += 0.05
            self.bobOffset = sin(self.phase) * 6

            // 气泡到点消失。
            //
            // ⚠️ **不另开一个 Timer**：这里本来每 1/30 秒就要跑一次，顺手
            //    检查一下比再养一个 timer 便宜得多，也少一处能写错的地方。
            if let hideAt = self.bubbleHideAt, Date() >= hideAt {
                self.bubbleText = nil
                self.bubbleHideAt = nil
            }

            self.needsDisplay = true
        }

        // ⚠️ 用 `RunLoop.main.add(_:forMode: .common)`，**不要**用
        //    `Timer.scheduledTimer` —— 后者只把 timer 加进 `.default` 模式，
        //    而用户一拖桌宠、一开菜单，主 run loop 就切到 eventTracking 模式，
        //    动画会停摆（表现是"拖着走的时候猫不动了"）。
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
    }

    private func stopAnimating() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    deinit {
        // Timer 会因为 weak self 变 nil 而自行退场，这里只是尽早收摊。
        animationTimer?.invalidate()
    }

    // MARK: - 绘制

    override func draw(_ dirtyRect: NSRect) {
        // ⚠️ 这里**刻意不填充背景**。
        //    窗口是透明的（isOpaque = false + backgroundColor = .clear），
        //    没画到的地方就保持透明。在这里填一层背景色，窗口立刻变成方块。
        //
        //    代价是：透明像素的点击会穿透到桌面。所以下面每一块要能被点到的
        //    内容，都必须**自己画一层不透明的底衬**。
        drawCat()
        drawProgress()
        drawBubble()
    }

    // MARK: 猫

    private func drawCat() {
        let rect = catRect
        guard rect.width > 0, rect.height > 0 else { return }

        if let image = catImage {
            drawShadow(under: rect)
            drawImage(image, in: rect, rounded: false)
        } else if let card = sourceImage {
            drawShadow(under: rect)
            drawImage(card, in: rect, rounded: true)
        } else {
            // 第 ③ 层降级：连图片都找不到。`swift run` 跑裸二进制时必然走到
            // 这里 —— 那时 Bundle.main 里根本没有 Contents/Resources/。
            drawFallbackDot(in: rect)
        }
    }

    private func drawShadow(under rect: NSRect) {
        // ⚠️ 这层阴影不只是好看。
        //
        //    抠图之后猫的背景是 alpha=0，而透明像素的点击会穿透到桌面 ——
        //    也就是说"能抓住来拖窗口"的范围只剩猫的剪影本身，细腿、胡须、
        //    尾巴尖几乎抓不住。这层阴影给了拖拽一个稳定的、够大的锚点。
        let shadow = NSRect(
            x: rect.midX - rect.width * 0.31,
            y: rect.minY + rect.height * 0.04,
            width: rect.width * 0.62,
            height: rect.height * 0.11
        )
        NSColor(calibratedWhite: 0, alpha: 0.10).setFill()
        NSBezierPath(ovalIn: shadow).fill()
    }

    private func drawImage(_ image: NSImage, in rect: NSRect, rounded: Bool) {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return }

        // 等比缩放塞进 rect（contain，不是 cover）。
        let scale = min(rect.width / size.width, rect.height / size.height)
        let drawRect = NSRect(
            x: rect.midX - size.width * scale / 2,
            y: rect.midY - size.height * scale / 2 + bobOffset,
            width: size.width * scale,
            height: size.height * scale
        )

        guard rounded else {
            // 抠好的猫：直接把带 alpha 的图盖上去。
            image.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)
            return
        }

        // 降级卡片：圆角裁掉，底下垫一层浅色，再描一圈淡边 ——
        // 否则照片在浅色桌面上没有边界，看起来像"糊了一块"。
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: drawRect, xRadius: 18, yRadius: 18).addClip()
        NSColor(calibratedWhite: 1.0, alpha: 0.94).setFill()
        NSBezierPath(rect: drawRect).fill()
        image.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()

        NSColor(calibratedWhite: 0, alpha: 0.12).setStroke()
        let border = NSBezierPath(roundedRect: drawRect, xRadius: 18, yRadius: 18)
        border.lineWidth = 1
        border.stroke()
    }

    /// 最老的粉色小圆。只在连照片都加载不到时出现。
    private func drawFallbackDot(in rect: NSRect) {
        let side = min(rect.width, rect.height)
        let diameter = side * 0.62
        let bodyRect = NSRect(
            x: rect.midX - diameter / 2,
            y: rect.midY - diameter / 2 + bobOffset,
            width: diameter,
            height: diameter
        )

        NSColor.systemPink.setFill()
        NSBezierPath(ovalIn: bodyRect).fill()

        let eyeDiameter = diameter * 0.16
        let eyeOffsetX = diameter * 0.17
        NSColor.black.setFill()
        for direction in [CGFloat(-1), CGFloat(1)] {
            let eyeRect = NSRect(
                x: bodyRect.midX + direction * eyeOffsetX - eyeDiameter / 2,
                y: bodyRect.midY + diameter * 0.10 - eyeDiameter / 2,
                width: eyeDiameter,
                height: eyeDiameter
            )
            NSBezierPath(ovalIn: eyeRect).fill()
        }
    }

    // MARK: 进度

    /// 未达标时显示 goal，达标后显示 stretchGoal —— 这样"至少 2000、最好 2800"
    /// 两个数字都能被看见，而不是让 2800 一上来就把 2000 顶掉。
    private var progressLabel: String {
        let target = todayML >= goalML ? stretchGoalML : goalML
        let mark = todayML >= goalML ? " ✓" : ""
        return "\(todayML) / \(target) ml\(mark)"
    }

    private func drawProgress() {
        // ---- 文字条
        //
        // ⚠️ 透明窗口上**不能裸画文字** —— 浅色桌面上直接看不见。
        // ⚠️ 颜色用固定的深灰，**不要用 `.labelColor`**：那个跟随系统深浅色
        //    外观，深色模式下会变成白字，撞上我们固定的浅色底衬就没了。
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor(calibratedWhite: 0.12, alpha: 1),
        ]
        let label = progressLabel as NSString
        let textSize = label.size(withAttributes: attributes)
        let pillWidth = min(textSize.width + 20, bounds.width - 16)
        let pill = NSRect(
            x: bounds.midX - pillWidth / 2,
            y: 68,
            width: pillWidth,
            height: max(textSize.height, 16)
        )

        NSColor(calibratedWhite: 1.0, alpha: 0.90).setFill()
        NSBezierPath(
            roundedRect: pill,
            xRadius: pill.height / 2,
            yRadius: pill.height / 2
        ).fill()

        label.draw(
            at: NSPoint(x: pill.midX - textSize.width / 2,
                        y: pill.midY - textSize.height / 2),
            withAttributes: attributes
        )

        // ---- 进度条
        let bar = Self.progressBarRect(within: bounds)

        // 先铺一条底色，否则 0 ml 的时候整条根本看不见。
        NSColor(calibratedWhite: 0, alpha: 0.15).setFill()
        NSBezierPath(
            roundedRect: bar,
            xRadius: bar.height / 2,
            yRadius: bar.height / 2
        ).fill()

        // 条长按 **stretchGoal** 算满格，goal 用一根刻度线标出来。
        let fraction = min(1, CGFloat(todayML) / CGFloat(max(stretchGoalML, 1)))
        if fraction > 0 {
            let filled = NSRect(
                x: bar.minX,
                y: bar.minY,
                // 至少给一个圆点宽，否则刚喝一口时那一点点会被圆角吃掉看不见。
                width: max(bar.height, bar.width * fraction),
                height: bar.height
            )
            let color: NSColor = todayML >= goalML ? .systemGreen : .systemBlue
            color.setFill()
            NSBezierPath(
                roundedRect: filled,
                xRadius: bar.height / 2,
                yRadius: bar.height / 2
            ).fill()
        }

        // goal 刻度线
        let goalFraction = CGFloat(goalML) / CGFloat(max(stretchGoalML, 1))
        let tickX = bar.minX + bar.width * goalFraction
        NSColor(calibratedWhite: 0, alpha: 0.45).setFill()
        NSBezierPath(rect: NSRect(
            x: tickX - 0.5,
            y: bar.minY - 2,
            width: 1,
            height: bar.height + 4
        )).fill()
    }

    // MARK: 气泡

    private func drawBubble() {
        guard let text = bubbleText else { return }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor(calibratedWhite: 0.12, alpha: 1),
        ]
        let string = text as NSString
        let textSize = string.size(withAttributes: attributes)

        let padH: CGFloat = 12
        let padV: CGFloat = 8

        // ⚠️ 宽度上限就是窗口宽度，**放不下会被裁**。所以文案必须短：
        //    "该喝水啦" / "+250 ml" / "今天达标了" 这个量级。
        let width = min(textSize.width + padH * 2, bounds.width - 16)
        let bubble = NSRect(
            x: bounds.midX - width / 2,
            y: bounds.height - 46,
            width: width,
            height: textSize.height + padV * 2
        )

        // ⚠️ 必须画不透明底衬，两个理由：
        //    (1) 透明窗口上裸画文字在浅色桌面上完全看不清；
        //    (2) 透明像素的点击会穿透到桌面 —— 画了东西才算"有实体"。
        NSColor(calibratedWhite: 1.0, alpha: 0.94).setFill()
        NSBezierPath(roundedRect: bubble, xRadius: 10, yRadius: 10).fill()

        NSColor(calibratedWhite: 0, alpha: 0.10).setStroke()
        let edge = NSBezierPath(roundedRect: bubble, xRadius: 10, yRadius: 10)
        edge.lineWidth = 1
        edge.stroke()

        // ⚠️ 气泡**不跟 bobOffset 浮动**。上下飘的文字会让人头晕，而且一眼
        //    就是"廉价感"的来源。浮动只作用在猫身上。
        string.draw(
            at: NSPoint(x: bubble.minX + padH, y: bubble.minY + padV),
            withAttributes: attributes
        )
    }
}
