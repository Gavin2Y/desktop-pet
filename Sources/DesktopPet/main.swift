import AppKit

// ⚠️ 未经编译验证 —— 见 README「未经编译验证」一节。
//
// SPM 可执行目标的入口。
//
// ⚠️ 这个文件**必须叫 main.swift**。Swift 里只有叫这个名字的文件才允许写
//    顶层代码，而顶层代码就是入口（等价于 C 的 main）。
//    换成别的名字、或者改用 `@main struct`，都需要另外的写法。
//
// 另一个顺带的好处：`swift-tools-version: 5.9` 的 Swift 5 语言模式下，
// 顶层代码不受 `@MainActor` 约束，所以这里可以直接裸调 AppKit 而不需要
// 任何并发标注。（这也是 Package.swift 里那条「不要升 6.0」的理由之一。）

let app = NSApplication.shared

// ⚠️ `NSApplication.delegate` 是 **weak** 引用。这里的 `let` 位于 main.swift 的
//    顶层，会变成全局变量、活到进程结束，所以它不会被提前释放。
//    （如果把这两行挪进某个函数里，delegate 会在函数返回时死掉，症状是
//     应用起来了但什么窗口都没有。）
let delegate = AppDelegate()
app.delegate = delegate

// ⚠️ 这里**故意不调** `app.setActivationPolicy(.accessory)`。
//    不显示 Dock 图标由 Info.plist 的 `LSUIElement` 负责，理由写在那份文件里。
//    两个一起用会让 Sonoma+ 把菜单栏图标扔进「被屏蔽的菜单栏项」。

app.run()
