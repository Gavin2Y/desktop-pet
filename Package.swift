// swift-tools-version: 5.9
//
// ⚠️⚠️ **这个 5.9 不要升级成 6.0。**
//
// tools-version 决定了**语言模式**：写 6.0 会让 Swift 6 语言模式成为默认，
// 而 Swift 6 语言模式**无条件开启**完整 data-race safety 检查 —— 违规从
// 「警告」变成「编译错误」。AppKit 这套代码里到处是主线程假设
// （NSWindow / NSView / NSStatusItem 都得在主线程碰），在 Swift 6 模式下会
// 炸出一大片 @MainActor / Sendable 错误。
//
// 写 5.9 则保持 Swift 5 语言模式，同样的问题只是警告 —— 编译能过。
//
// 这个仓库的作者（以及写它的那个 AI）**都没有 macOS 环境可以编译验证**，
// 所以这里刻意选最保守的语言模式。见 README 的「未经编译验证」一节。

import PackageDescription

let package = Package(
    name: "DesktopPet",
    platforms: [
        // ⚠️ 这个值必须和 Resources/Info.plist 里的 LSMinimumSystemVersion
        //    对应：.macOS(.v13) ↔ "13.0"。改一个就得改另一个。
        .macOS(.v13)
    ],
    products: [
        .executable(name: "DesktopPet", targets: ["DesktopPet"])
    ],
    targets: [
        .executableTarget(
            name: "DesktopPet",
            path: "Sources/DesktopPet"
            // ⚠️ 这里**刻意什么都不加**。
            //    尤其不要加：
            //      swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
            //      swiftSettings: [.unsafeFlags(["-strict-concurrency=complete"])]
            //    那会把并发检查拉满，在上面那个理由下等于自找编译失败。
        )
    ],
    // 第二重保险：万一将来有人把 tools-version 升到了 6.x，这一行仍然把
    // 语言模式钉死在 Swift 5。（tools-version 6.0 里这个参数改名叫
    // swiftLanguageModes，届时这一行会失效 —— 但也只是个提醒。）
    swiftLanguageVersions: [.v5]
)
