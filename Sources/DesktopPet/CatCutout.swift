import AppKit
import CoreImage
import CoreVideo
import ImageIO
import Vision

// 从照片里把猫抠出来。
//
// 这一层的公开接口只有两个：
//   - `loadSource(maxPixel:)`   —— 把大图降采样成能用的输入（快，主线程可以调）
//   - `cachedOrBuild(from:)`    —— 抠图，带磁盘缓存（慢，必须在后台队列调）
//
// 抠图本身用 Vision 的 `VNGenerateForegroundInstanceMaskRequest`（macOS 14+）。
// 它把"主体"之外的一切变成透明，正好就是我们要的效果 —— 顺带还能把照片左下角
// 那个 HUAWEI 水印切掉（水印不是前景实例，且裁到猫的包围盒之后多半落在框外）。
//
// ⚠️ 三层降级（每一层都是上一层的兜底）：
//     ① 抠图成功        → 带 alpha 的猫
//     ② 失败 / 系统 <14 → 圆角照片卡片（用的是降采样后的原图，不抠）
//     ③ 连图都找不到     → 退回 PetView 里画的那个粉色圆
//
//   第 ③ 层**不是死代码**：`swift run` 跑的是裸二进制而不是 .app，此时
//   `Bundle.main` 指向可执行文件所在目录，`Contents/Resources/` 根本不存在，
//   取图必然返回 nil。而 README 第 2 步就是让人 `swift run` 的 ——
//   没有这一层，用户会看到一个空窗口，然后以为代码写错了。

enum CatCutout {

    /// 抠图结果最多保留多少像素宽/高。
    ///
    /// 最终只画 160 pt，**留 512 已经远超所需**（视网膜屏下 160 pt ≈ 320 px）。
    /// 但 Vision 的输入不能太小，否则主体分割质量下降，所以输入用 1024、
    /// 输出收到 512。
    private static let cutoutMaxPixel: CGFloat = 512

    /// ⚠️ `CIContext` 很贵（内部有 GPU/CPU 上下文和缓存），**必须复用**，
    ///    不能每次调用都 new 一个。
    private static let ciContext = CIContext()

    // MARK: - ① 加载 + 降采样

    /// 从 bundle 里读 cat.jpg，降采样到 `maxPixel` 见方以内。
    ///
    /// 失败返回 nil（调用方走第 ③ 层降级）。
    static func loadSource(maxPixel: CGFloat = 1024) -> CGImage? {
        // ⚠️ 用 `Bundle.main`，**不要**用 `Bundle.module`。
        //    本项目的 .app 是 build.sh 手工组装的，SPM 的 resource bundle
        //    根本不存在，`Bundle.module` 会直接 trap。
        guard let url = Bundle.main.url(forResource: "cat", withExtension: "jpg") else {
            return nil
        }

        // ⚠️⚠️ **绝不要写 `NSImage(contentsOf: url)`。**
        //    那是一张 3648×2736 的图，全解码后常驻约 40 MB，而且会在主线程上
        //    花掉几百毫秒。桌宠只需要 160 pt 宽。
        //
        //    `kCGImageSourceShouldCache: false` 是必须的 —— 否则
        //    `CGImageSourceCreateWithURL` 可能顺手把全图解码缓存起来，
        //    降采样就白做了。
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(
            url as CFURL,
            sourceOptions as CFDictionary
        ) else {
            return nil
        }

        let thumbOptions: [CFString: Any] = [
            // 不依赖文件里已有的 EXIF 缩略图 —— 那张可能小得没法用。
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            // ⚠️ **必须开。** 这张照片是华为拍的，EXIF 里有 orientation。
            //    不开的话猫会躺着。
            kCGImageSourceCreateThumbnailWithTransform: true,
            // 立刻解码，别把解码推迟到第一次绘制时（那会卡住主线程）。
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxPixel),
        ]

        // ⚠️ 已知代价：这个调用有一次性的**瞬时内存尖峰**，可能明显大过最终
        //    位图（社区报告过 43 MB 的产物伴随 230 MB 尖峰，且不同系统版本
        //    行为不一致）。启动时调一次可以接受，**别把它放进循环里**。
        return CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            thumbOptions as CFDictionary
        )
    }

    // MARK: - ② 抠图（带磁盘缓存）

    /// 有缓存就读缓存，没有就跑 Vision 并写缓存。
    ///
    /// ⚠️ **必须在后台队列调用** —— Vision 首次推理要几百毫秒到一两秒，
    ///    在主线程同步跑会让窗口白屏且不报任何错，看起来像应用卡死。
    static func cachedOrBuild(from source: CGImage) -> CGImage? {
        if let cached = loadFromCache() {
            return cached
        }

        // 失败了就返回 nil，**并且不写缓存** —— 见下面 writeCache 的注释。
        guard let fresh = makeCutout(from: source) else { return nil }

        writeCache(fresh)
        return fresh
    }

    /// 真正的抠图。
    private static func makeCutout(from source: CGImage) -> CGImage? {
        // ⚠️⚠️ 这一行是**编译期**的硬门槛，不是运行时保险。
        //    `VNGenerateForegroundInstanceMaskRequest` 和 `VNInstanceMaskObservation`
        //    **两个类型本身**都标了 macOS 14，而 deployment target 是 13.0 ——
        //    所以**整个函数体**都得待在这个 guard 里面，连碰 `request.results`
        //    都不行。少了它会直接编译不过（这是好事，等于编译器替我们检查）。
        guard #available(macOS 14.0, *) else { return nil }

        let input = CIImage(cgImage: source)
        let handler = VNImageRequestHandler(ciImage: input, options: [:])
        let request = VNGenerateForegroundInstanceMaskRequest()

        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        // ⚠️ `request.results` 的元素类型**已经**是 `VNInstanceMaskObservation`，
        //    不需要（也不应该）再写 `as? VNInstanceMaskObservation`。
        //    旧博客里那种写法是多余的，而且可能触发告警。
        guard let observation = request.results?.first else { return nil }

        let buffer: CVPixelBuffer
        do {
            buffer = try observation.generateMaskedImage(
                // 所有前景实例。`allInstances` 是 IndexSet，不含背景。
                ofInstances: observation.allInstances,
                // ⚠️⚠️ **必须传上面那个 handler 本身**，不能新建一个。
                //     文档原话是 "the image request handler containing the
                //     source image to mask"。传错会抛错或拿到空图。
                from: handler,
                // 裁到刚好包住实例的最小矩形。
                // 这也是顺带把左下角水印切掉的那一步。
                croppedToInstancesExtent: true
            )
        } catch {
            return nil
        }

        // CVPixelBuffer → CIImage →（先缩放）→ CGImage
        let masked = CIImage(cvPixelBuffer: buffer)
        let extent = masked.extent
        guard extent.width > 1, extent.height > 1 else { return nil }

        // ⚠️ **先缩放，再 createCGImage。**
        //    直接 createCGImage 全分辨率会常驻约 3648×2736×4 ≈ 40 MB，
        //    而我们最终只画 160 pt。缩放发生在 CIImage 的惰性管线里，
        //    几乎不花钱；但顺序反了就没意义了。
        //
        //    `transformed(by:)` 以原点为基准缩放，而 `CIImage(cvPixelBuffer:)`
        //    的 extent 原点就是 (0,0)，所以缩放后原点仍是 (0,0)，
        //    下面用 `scaled.extent` 取到的就是完整图。
        let scale = cutoutMaxPixel / max(extent.width, extent.height)
        let scaled = scale < 1
            ? masked.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            : masked

        // 返回 Optional，必须 guard。生成的图**保留 alpha**（抠图的价值就在这），
        // 转 NSImage 时不要碰 isOpaque。
        return ciContext.createCGImage(scaled, from: scaled.extent)
    }

    // MARK: - 磁盘缓存

    /// 缓存路径。用 bundle id 当目录名，和 UserDefaults 的域保持一致。
    private static var cacheURL: URL? {
        guard let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }

        let directory = base.appendingPathComponent(
            "top.gavin-nas.desktoppet",
            isDirectory: true
        )
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        // ⚠️ 文件名里的 `-v1` 是**缓存版本号**。将来改了抠图管线（换 maxPixel、
        //    换 croppedToInstancesExtent……），把 v1 改成 v2 就自动失效重算，
        //    完全不用写清理逻辑。
        return directory.appendingPathComponent("cat-cutout-v1.png")
    }

    private static func loadFromCache() -> CGImage? {
        guard let url = cacheURL,
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        // NSImage → CGImage 这一步在 macOS 10.6+ 是可用的。
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    /// ⚠️ **只在抠图成功时调用。**
    ///
    ///    失败也写缓存的话，一次偶发失败（比如系统刚启动时 Vision 的模型还没
    ///    就绪）会被**永久固化**下来 —— 用户会永远看到降级卡片，而且
    ///    "重启也没用"，因为缓存文件一直在。
    private static func writeCache(_ image: CGImage) {
        guard let url = cacheURL,
              let rep = NSBitmapImageRep(cgImage: image),
              let png = rep.representation(using: .png, properties: [:]) else {
            return
        }
        // 写不进去也无所谓（只读磁盘、沙箱限制……），下次启动再算一遍而已。
        try? png.write(to: url)
    }
}
