# desktop-pet

一个 macOS 桌面宠物，本职工作是**监督你喝水**。原生 Swift + AppKit，透明无边框
窗口，一只从照片里（运行时用 Vision 抠出来的）猫趴在桌面右下角，**每 20 分钟**
提醒你喝一杯，下面**三个按钮**记一杯是多少毫升，进度条盯着当天**至少 2000 ml、
最好 2800 ml** 的目标。

构建在 **GitHub Actions 的 macOS runner** 上跑（本机是 Linux，构建不了 macOS 应用），
产物挂成 GitHub Release asset，由 n8n 拉下来放进局域网交付站供下载。

---

## ⚠️ 状态：骨架验过，**喝水功能一行都没验过**，运行全都没验过

按可信度从高到低：

| 范围 | 状态 |
|---|---|
| 仓库结构 / `build.sh` / `workflow` / `Info.plist` 的语法 | ✅ 已在 CI 真跑过 |
| 骨架那 5 个 Swift 文件（编译、universal 产物、签名、`ditto` 打包自检） | ✅ CI run #2 验过 |
| **新加的喝水功能**（`CatCutout` / `WaterStore` / `Reminder` + `PetView`/`StatusItem`/`AppDelegate` 的改动） | ❌ **一行都没编译过** |
| 应用跑起来之后的**一切行为** | ❌ 没验过 |
| `挂到 GitHub Release` 那一步 | ❌ 一次都没跑过（只在推 tag 时触发） |

> 这条警告在 2026-10-07 缩过一次水（「一行都没编译过」→「编译过了」），
> 同一天又加回来一半 —— 因为喝水功能是新写的，**它确实一行都没编译过**。
> 往哪个方向都不夸大。

### 骨架在 CI 上真跑过并通过的（run #2，2026-10-07）

| 项 | 证据 |
|---|---|
| 当时的 5 个 Swift 文件能编译 | `swift build` 通过，**arm64 和 x86_64 都编了**。⚠️ 现在有 8 个 —— 新加的 3 个**没验过** |
| 产物是 universal | `lipo -archs` → `x86_64 arm64` |
| `.app` 组装正确 | `plutil -lint` OK |
| ad-hoc 签名有效 | `codesign --verify --strict` → `valid on disk` / `satisfies its Designated Requirement` |
| `ditto` 打包**没有**破坏签名 | 脚本末尾**从 zip 解出来再验一次**，通过 |
| Actions 能出产物 | `DesktopPet-0.0.0.zip`，30K |

跑它的环境：`macos-15-arm64` / macOS 15.7.9 / Xcode 16.4 / Swift 6.1.2。

### 仍然**完全没验证过**的

**一、跑起来之后的行为**（就是下面清单里 2~5 那几歩）：

- 应用**能不能启动**
- 窗口是不是真的**透明**（还是会出现一块灰底）
- 猫**会不会动**、**能不能拖**、三个按钮**点不点得动**
- **Vision 抠图在这张具体照片上到底行不行**（边缘质量、水印去没去）
- 菜单栏图标在不在、菜单项点不点得动
- Gatekeeper 那一关

**二、`挂到 GitHub Release` 那一步。** 它只在**推 tag** 时执行，而到目前为止
CI 都是手工 `workflow_dispatch` 触发的 —— 所以那一步**一次都没跑过**，
是整条流水线上唯一没被执行过的环节。（n8n 拉产物那一段则压根还没建。）

**编译通过 ≠ 跑得起来。** AppKit 绝大多数翻车都是运行时才现形的，而这台
Linux 机器**物理上跑不了 macOS 应用**（SwiftUI/AppKit 在 Linux 上不存在 ——
不是"没装"，是"没有这个东西"）。所以下面那份清单还剩大半。

### 上 Mac 后请按这个顺序确认

⚠️ **第 1、6、7 步已经由 CI 验过了**，还留在表里是因为本地复现一遍仍然值得
（CI 的 runner 和你手上的 Mac 未必同一个系统版本）。**真正没验过的是 2~5 和 8~9 步。**

1. ~~先确认能编译~~ → ✅ **CI 已验**。⚠️ 但那次**只验到旧骨架那 5 个文件**；
   喝水功能的新文件（`CatCutout` / `WaterStore` / `Reminder` 和一堆改动）
   **一次都没编译过**，所以这一步现在最值得重跑。
2. **再确认能跑**：`swift run` —— 窗口出现在屏幕右下角，菜单栏有一个脚印图标。
   ⚠️ 这里**必然**看到第 ③ 层降级（画出来的粉色小圆），因为 `swift run` 跑的是
   **裸二进制**不是 `.app`，`Bundle.main` 里没有 `Contents/Resources/`，
   取不到猫的照片。**这不是 bug**，是设计好的兜底。要看到真猫得跑 `.app`
   （第 6 步打完包之后）。
3. **重点看透明**：窗口周围**不应该**有灰色或白色的方块。有的话是
   `isOpaque` / `backgroundColor` 那条线的问题。
4. **试试拖动**：按住**猫身上**拖，应该跟着走；**按住下面三个按钮的区域不应该拖窗口**。
   ⚠️ 抠图之后能抓住的范围只剩猫的剪影（透明像素的点击会穿透到桌面），
   所以猫底下那层淡阴影是**故意**画的 —— 它才是稳定的抓取点。
5. **点三个按钮**：`200` / `250` / `300`。每点一下应该冒一句气泡、进度条往前长。
   菜单栏 →「退出桌面宠物」也要能点（**灰的**说明 `NSMenuItem` 的 `target` 没生效）。
6. ~~最后验打包~~ → ✅ **CI 已验**（含从 zip 解包后重验签名那步）。
7. ~~才轮到 Actions~~ → ✅ **CI 本身已跑通**（手工 `workflow_dispatch`）。
   ⚠️ 但**当时没打 tag**，而 `挂到 GitHub Release` 那一步只在 tag 触发时才执行 ——
   所以**它到现在一次都没跑过**。等你在 Mac 上验过 2~5 步、打第一个 tag 时，
   这条才算真的走完。
8. **跑 `.app`，验抠图**（这是唯一能看到真猫的路径）：第一次启动应该先看到
   **圆角照片卡片**，然后"啪"一下变成**没有背景的猫**。
   - 一直停在卡片不变 → Vision 抠图失败。
   - 猫身上还带着 **HUAWEI 水印** → 抠图的包围盒把水印框进去了。
   - 猫**躺着** → EXIF orientation 没处理。
9. **验提醒节奏**：把 `Reminder.interval` 临时改成 30 秒，别真等 20 分钟。
   要点：记一杯之后 20 分钟内不该再催；把系统时间调到 23:00 应该静音。

> 心里有数：**从第 2 步开始每一步都可能失败**，见下面「我（作者）最可能写错的地方」。

---

## 喝水监督是怎么运作的

| | |
|---|---|
| 提醒间隔 | **20 分钟** |
| 一杯 | **200 / 250 / 300 ml** 三个按钮（菜单栏里也有一个「记录一杯 250 ml」） |
| 当天目标 | 至少 **2000 ml**，最好 **2800 ml** |
| 夜间静音 | **22:00–08:00**，默认开，可在菜单里关 |
| 跨天 | 自动重置（用 `isDate(_:inSameDayAs:)` 判，不是比时间戳） |

进度条按 **2800** 算满格，**2000** 那根刻度线单独画出来 —— 这样"至少"和"最好"
两个数字同时可见。文字则未达标时显示 `1200 / 2000 ml`，达标后切成
`2200 / 2800 ml ✓`。

几个刻意的设计，理由都写在代码注释里：

- **不从 tick 计数推导时间，每次都拿墙上时钟重新比。** `Timer` 在系统睡眠期间
  不走，数 tick 的写法合上盖子睡一夜再打开会一口气补发一串提醒；比时间点的
  写法最多只弹一条。
- **记一杯之后 20 分钟内不再催。** 刚喝过还催就是骚扰。（想要"不管喝没喝、
  每 20 分钟固定催一次"，删掉 `AppDelegate.record(ml:)` 里的 `reminder.noteDrank()`
  即可。）
- **猫是从照片里抠的，不是画上去的。** 用 Vision 的
  `VNGenerateForegroundInstanceMaskRequest`（**macOS 14.0+**），结果缓存在
  `~/Library/Application Support/top.gavin-nas.desktoppet/cat-cutout-v1.png`，
  所以推理只在第一次启动跑一次。
- **抠图失败不影响使用**，有三层降级：抠图 → 圆角照片卡片 → 画的粉色小圆。

---

## 它是怎么运作的

```
  你（在 Mac 上）                 GitHub                     这台 homeserver
        │                            │                             │
   git push tag v0.1.0 ────────────► │                             │
                                     │                             │
                          GitHub Actions (macos-15)                │
                            swift build                            │
                            ├─ 组装 DesktopPet.app                 │
                            ├─ ad-hoc 签名                         │
                            └─ ditto 打包成 zip                    │
                                     │                             │
                          挂成 Release asset                       │
                    .../releases/download/v0.1.0/DesktopPet-0.1.0.zip
                                     │                             │
                                     └──── n8n 拉取（无需 token）──► │
                                                                   │
                                        /srv/delivery/desktop-pet/0.1.0/
                                                                   │
                                          nginx（只读挂载）          │
                                                                   ▼
                                          http://192.168.3.116:8448/desktop-pet/
```

**中间那条「n8n 拉取」目前还没建** —— 本次只把接口留好（见
`.github/workflows/build.yml` 末尾的注释）。n8n 那边以后再说。

---

## 目录

```
desktop-pet/
├── README.md
├── .gitignore                        凭据块在最前面（workspace 统一规矩）
├── Package.swift                     SPM 清单。⚠️ tools-version 5.9 不要升级
├── Resources/
│   ├── Info.plist                    app bundle 元数据；LSUIElement 在这里
│   └── cat.jpg                       猫的原图（2.4 MB）。运行时用 Vision 抠图
├── Sources/DesktopPet/
│   ├── main.swift                    入口。必须叫 main.swift
│   ├── AppDelegate.swift             装配窗口 / 菜单栏 / 记账本 / 提醒器
│   ├── PetWindow.swift               透明/置顶/可拖拽的 NSWindow 子类
│   ├── PetView.swift                 画猫 + 气泡 + 进度条 + 三个按钮
│   ├── CatCutout.swift               读图 + 降采样 + Vision 抠图 + 磁盘缓存
│   ├── WaterStore.swift              今日毫升数 + 跨天重置（UserDefaults）
│   ├── Reminder.swift                20 分钟节奏 + 夜间静音
│   └── StatusItem.swift              菜单栏菜单
├── scripts/
│   └── build.sh                      组 .app → 签名 → 用 ditto 打包
└── .github/workflows/
    └── build.yml                     macos-15 上构建 + 发 Release
```

---

## 在 Mac 上开发

```sh
swift build          # 编译
swift run            # 直接跑。⚠️ 只会看到第 ③ 层降级（画的粉色圆）——
                     #    裸二进制里没有 Contents/Resources/，取不到猫的照片

bash scripts/build.sh   # 想知道抠图长什么样，得跑这个出来的 .app

xed .                # 用 Xcode 打开这个 SPM 包
```

**本项目刻意不用 `.xcodeproj`。** `project.pbxproj` 是 UUID 密布的大 plist，
手写极易出错，而这个仓库的作者**没有 macOS 环境可以验证** —— 错一个 UUID 就是
一个打不开的项目文件。`Package.swift` 是普通 Swift 代码，人能读能审，
而且 Xcode 可以直接打开 SPM 包。代价是 SPM 只出裸二进制，需要 `build.sh`
手工组成 `.app` —— 那是确定性的 shell，比赌一个 pbxproj 可靠得多。

---

## 构建与发布

```sh
bash scripts/build.sh                        # → dist/DesktopPet-0.0.1.zip
ARCHS=arm64 bash scripts/build.sh            # 单架构（universal 出问题时用）
VERSION=1.2.3 BUILD_NUMBER=42 bash scripts/build.sh
```

正式发布走 tag：

```sh
git tag v0.1.0
git push origin v0.1.0
```

CI 会构建、自检、把 zip 挂到 GitHub Release 上。

### 三条不能破的规矩

1. **签名必须在所有拷贝完成之后。** 签名后再改 bundle 里的任何东西（哪怕只是
   改一行版本号），用户看到的报错是「**应用已损坏，无法打开**」—— 而原因看起来
   跟"改了个版本号"毫无关系。顺序铁律：拷贝完成 → `codesign` → 只读 → 打包。

2. **打包必须用 `ditto -c -k --keepParent`，不能用 `zip -r`。** `zip` 不保留
   符号链接和扩展属性，解压出来的 app 与签名时不匹配。`build.sh` 末尾会**真的
   解压一次再验签名**，就是为了把这个失败模式在构建时当场抓住。
   也不要加 `--sequesterRsrc` —— Apple 明说它不适合应用分发。

3. **交付必须走 Release asset，不能用 Actions 的 artifact。**
   `upload-artifact` 会把所有文件设成 `644`，`Contents/MacOS/DesktopPet` 的
   可执行位就没了，用户下载解压后应用打不开。workflow 里那个 artifact
   步骤**只为了调试**。

### 为什么钉 `macos-15` 而不是 `macos-latest`

`macos-latest` 已经从这个镜像滚到 `macos-26` 了，会在你不知情的时候换工具链，
某天 CI 突然变红而代码一个字没动。也**不要**碰 `macos-15-large` / `-xlarge`：
larger runner 即使在公开仓库上也要计费。标准的 `macos-15` 在公开仓库上
完全免费、不扣额度。

---

## 拿到 zip 之后怎么打开

下载、解压、把 `DesktopPet.app` 拖进「应用程序」。首次打开会被 Gatekeeper 拦下 ——
因为这个应用**没有 Apple 开发者签名**（ad-hoc 签名只满足内核那一层，
`build.sh` 里解释了为什么）。

**⚠️ 右键 →「打开」这个老办法在 macOS 15 Sequoia 上已经失效了。** Apple 明确
移除了 Control-click 绕过 Gatekeeper 的能力。现在正确的做法是：

- **方法一**：双击一次让它被拦 → 打开「系统设置」→「隐私与安全性」→ 找到
  DesktopPet 那条 → 点「仍要打开」。
- **方法二**（命令行）：`xattr -dr com.apple.quarantine /Applications/DesktopPet.app`

> **一个真实的省事点**：用 `curl` 下载的文件**不会**被附加 quarantine 属性
> （只有浏览器、邮件这类 GUI 应用才会）。所以将来 n8n 用 `curl` 拉产物的话，
> 经那条路下去的应用在 Mac 上**不会**遇到 Gatekeeper 拦截。
> 这也是想让「自动发布」真正好用的一个实际理由。

---

## 产物怎么落到交付站

交付站（`home-server-services` 里的 `apps/delivery`）会把宿主机
`/srv/delivery` 下的内容列出来供局域网下载。约定是：

```sh
/srv/delivery/
└── desktop-pet/           ← 一个项目一个目录
    └── 0.1.0/             ← 版本号
        └── DesktopPet-0.1.0.zip
```

**两条必须遵守的**（都是从交付站那边继承来的硬约束）：

1. **⚠️ 目录权限必须是 `0755`。** 那边的 nginx 跑在 **uid 101**，对产物来说是
   "其他人"。用 `0700` 建目录的话网页上是 **403**，而症状看起来像 Ingress 配错了。
2. **⚠️ 只放公开的东西。** 那个站**没有认证**，局域网里谁都能列出目录 ——
   而目录名本身就是信息（项目名、版本号）。

> 这三条不是这里定的，是交付站那边定的。写在这里是因为**跨仓库的约束最容易
> 在另一个仓库里被忘掉**。完整理由见 `home-server-services/README.md`
> 的「delivery：产物目录怎么用（和怎么弄坏）」。

---

## 作者最可能写错的地方

按翻车概率排序。**编译和打包已经由 CI 验过（run #2），但「跑起来之后」的事一行都没验过** ——
所以第 3~7 条仍然是最可能撞上的，那份清单是诚实交代而不是谦虚。

| # | 症状 | 大概是什么 |
|---|---|---|
| 1 | 一大堆 `@MainActor` / `Sendable` 编译错误 | `Package.swift` 的 tools-version 被改成了 6.0。参见那个文件开头的警告 |
| 2 | `cp: .../DesktopPet: No such file` | 有人在 `build.sh` 里硬编码了产物路径。已经用 `--show-bin-path` 避开了，但如果 SwiftPM 又改了行为，看那一步的日志 |
| 3 | 窗口是**灰的/黑的方块** | 透明那条线：`isOpaque` / `backgroundColor` / 或者视图里不小心填了背景 |
| 4 | 窗口**根本不出现** | `makeKeyAndOrderFront` 而不是 `orderFrontRegardless`（borderless 窗口 `canBecomeKey` 默认是 false，前者会静默失败） |
| 5 | 小人**拖不动** | borderless 窗口的拖拽是自己实现的，看 `PetWindow.sendEvent` |
| 6 | 菜单栏**图标一闪就没了** | `NSStatusItem` 没有被强引用 |
| 7 | 菜单项是**灰的**、点了没反应 | `NSMenuItem` 的 `target` 没设 |
| 8 | 用户报「应用已损坏」 | 打包用了 `zip` 而不是 `ditto`，或者签名之后又改了 bundle |
| 9 | CI 报 Node 20 相关的错 | action 版本过期了。用 `checkout@v5` / `upload-artifact@v7` / `action-gh-release@v3`（这几个版本号是查来的，值得在 action 页面确认一次） |
| 10 | release 步骤报 `Resource not accessible by integration` | 缺 `permissions: contents: write`，或者仓库级的 workflow permission 是 read-only（job 级覆盖不了它） |
| 11 | 全屏应用时看不见小人 | **已知无解**，不是 bug。别把它当需求 |
| 12 | `build.sh: line N: XXX?: unbound variable`，变量名后面跟着一个乱码字符 | 在中文提示语里写了 `$变量` 而后面**紧跟全角标点**（`）`、`，`、`：`）。macOS 自带的 `/bin/bash` 是 **3.2**，会把那个多字节字符的头一个字节吃进变量名，`set -u` 下就报 unbound。**写成 `${变量}`。**⚠️ 在 Linux 上复现不出来（本机 bash 5.3 已修多字节处理），这个坑只在 CI 或 Mac 上现形 —— 2026-10-07 真的踩过，CI run #1 就挂在这 |
| 13 | **一直是圆角照片卡片，永远不变抠图** | Vision 抠图失败（`results` 为空 / `perform` 抛错）；或系统 < macOS **14**（抠图 API 的下限）走了 `#available` 的 else 分支；或 `swift run` 里取不到图。⚠️ 最后这条在 `swift run` 下**必然发生**，见上文第 2 步 |
| 14 | 抠出来的猫**带着 HUAWEI 水印** | 水印没被当成前景实例、又正好落在猫的包围盒里。`croppedToInstancesExtent: true` 能大幅降低概率（裁到猫的框，左下角多半在框外），**但没验证过** |
| 15 | **按钮点不动 / 要点两下** | ① `PetWindow.sendEvent` 里那个分支误用了 `return` 而不是 `break`（事件到不了按钮）；② 用了不画底衬的 bezel style → 按钮区域是透明的 → 点击被 WindowServer **穿透到桌面**；③ macOS 26.3/26.4 那个 `.style.remove(.titled)` 的穿透回归（有论坛报告，未验证） |
| 16 | **按按钮时窗口跟着跑** | `dragExclusionRect` 没生效：矩形算成了视图坐标、或者 `PetView.controlsHeight` 和按钮的实际位置对不上、或者 `syncDragExclusionRect()` 压根没被调用 |
| 17 | **夜间静音完全不生效**，22:00 后照样提醒 | 判断写成了 `hour >= 22 && hour < 8` —— 这个条件**永远为假**。必须是 `\|\|` |
| 18 | **到点不提醒**，尤其"开着菜单等"的时候 | timer 用了 `Timer.scheduledTimer`（只进 `.default` 模式），用户一拖窗口/一开菜单，run loop 切到 eventTracking 模式就停摆。必须 `RunLoop.main.add(timer, forMode: .common)` |
| 19 | 唤醒后不提醒，或者要等一个 tick 才恢复 | 没注册 `NSWorkspace.didWakeNotification`；或者注册到了 `NotificationCenter.default` 而不是 `NSWorkspace.shared.notificationCenter`（**用错了一辈子收不到，而且不报错**） |
| 20 | **跨天不重置**，或者一天重置好几次 | 用了 `Calendar.current`（快照）而不是 `Calendar.autoupdatingCurrent`；或者用 `Date` 相等比较代替 `isDate(_:inSameDayAs:)` |
| 21 | **按钮/进度那块挡住了桌面点击**（比以前更严重） | 调了 `setIgnoresMouseEvents(_:)`（**哪怕传 `false`**），或者给 contentView 设了 `wantsLayer = true` —— 两者都会**永久关闭**逐像素穿透 |
| 22 | 拖拽只能抓住猫身上很窄的一块 | 透明像素穿透（WindowServer 系统行为，不是 bug）。猫底下那层淡阴影就是为这个画的 |
| 23 | **猫是躺着的** | 没开 `kCGImageSourceCreateThumbnailWithTransform`，EXIF orientation 没处理 |
| 24 | 打包后**找不到图片** | `cp` 加在了 `codesign` **之后**（顺序铁律）；或者用了 SPM 的 `resources:` / `Bundle.module` —— 手工组装的 bundle 里那个会直接 trap |
| 25 | 点一下桌宠，**当前编辑的 App 失去焦点** | `canBecomeKey = true` 的无边框 NSWindow 的**固有行为**，点击必然激活本应用。唯一解法是换 `NSPanel` + `.nonactivatingPanel`（那是另一套风险）。本方案选择接受 |
| 26 | 启动后**卡 1~2 秒**窗口才有内容 | Vision 跑在主线程了。必须在 `DispatchQueue.global` 里跑 |

---

## 已知限制

- **别人进入全屏应用时，桌宠可能看不见**，即使设了 `.fullScreenAuxiliary`。
  这是 Apple 论坛上反复出现的问题，没有可靠解法。
- **点一下桌宠，你正在打字的那个应用会失去焦点。** 这是 `canBecomeKey = true`
  的无边框 NSWindow 的固有行为，不点它就没事。唯一的解法是换成
  `NSPanel` + `.nonactivatingPanel`，但那是另一套风险，本方案选择先接受。
- **能抓住来拖的只有猫的剪影。** 透明窗口里没画东西的地方，点击会**穿透到桌面**
  —— 所以抠图之后，猫的细腿、胡须、尾巴尖都很难抓。底下那层淡阴影是故意画的，
  它才是稳定的抓取点。
- **窗口从 160×160 涨到了 200×300**，因为要在猫下面放进进度和三个按钮。
  ⚠️ 如果"透明区域穿透"这条机制在你的系统上不成立，**变大的窗口会挡住更多桌面点击**。
  这是这次改动里唯一可能让现状**变差**的地方，上机时请专门试一下。
- **猫的照片在公开仓库里。** 它就是这个 app 的脸，不放进仓库就没法构建。
- **没有代码签名**（没买 Apple 开发者账号）。每次给别人都要过一遍 Gatekeeper。
- **只在 macOS 13+ 上跑**（`Package.swift` 的 `.macOS(.v13)` 和 `Info.plist` 的
  `LSMinimumSystemVersion`，改一个就得改另一个）。

  > **关于「要在 macOS 27 上跑」**：不用改任何东西。deployment target 是**最低**
  > 版本而不是目标版本，为 13.0 编译的二进制在 26 / 27 上照跑 —— macOS 的兼容性
  > 是单向的。把它写成 27.0 反而会把 26 及以前**全部挡掉**。而且**也写不出来**：
  > `swift-tools-version: 5.9` 下 `.macOS(...)` 枚举最高只到 `.v14`，
  > `.v27` 要 tools-version 6.4，而升到 6.x 会同时打开 Swift 6 语言模式 ——
  > 和本项目「绝不升 6.0」的硬约束直接对撞。
  >
  > 需要 macOS 14 的地方（Vision 抠图）用 `if #available(macOS 14.0, *)` 包住，
  > 那是**编译器强制**的：忘了写就编译不过。这是"安全的失败"。
- **没有自动更新**。要新版本就重新下载。

---

## 相关仓库

| 仓库 | 关系 |
|---|---|
| `home-server-services` | 交付站（`apps/delivery`）在那里。产物最后落到那一边的 `/srv/delivery` |
| `paac` | n8n 工作流用代码管理。将来「拉产物 → 放交付站」那条线大概率写在那里 |

> 这个仓库托管在 **GitHub** 而不是 Gitee —— 和另外三个仓库不一样。
> 原因是硬的：**GitHub Actions 是 Swift 方案能自动出产物的唯一路径**
> （Gitee 没有 macOS runner），而 GitHub Actions 只认 GitHub 上的仓库。
> 这是明知而为的取舍，不是疏忽。
