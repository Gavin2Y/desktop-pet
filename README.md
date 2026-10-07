# desktop-pet

一个 macOS 桌面宠物。原生 Swift + AppKit，透明无边框窗口，一只会在桌面上浮动、
可以拖着走的小人。

构建在 **GitHub Actions 的 macOS runner** 上跑（本机是 Linux，构建不了 macOS 应用），
产物挂成 GitHub Release asset，由 n8n 拉下来放进局域网交付站供下载。

---

## ⚠️ 编译和打包**已经验过了**，运行**还没有**

这条警告在 2026-10-07 缩过一次水。**之前写的是「一行都没编译过」，那个说法已经过期了** ——
CI 现在真的把它编出来了。这里改成准确的说法，两个方向都不夸大。

### 已经在 CI 上真跑过并通过的（run #2，2026-10-07）

| 项 | 证据 |
|---|---|
| 5 个 Swift 文件能编译 | `swift build` 通过，**arm64 和 x86_64 都编了** |
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
- 小人**会不会动**、**能不能拖**
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
（CI 的 runner 和你手上的 Mac 未必同一个系统版本）。**真正没验过的是 2~5 步。**

1. ~~先确认能编译~~ → ✅ **CI 已验**。本地 `swift build` 仍值得跑一遍。
2. **再确认能跑**：`swift run` —— 应该出现一个粉色的小圆点飘在屏幕右下角，
   菜单栏有一个脚印图标，点它能看到「退出桌面宠物」。
3. **重点看透明**：窗口周围**不应该**有灰色或白色的方块。有的话是
   `isOpaque` / `backgroundColor` 那条线的问题。
4. **试试拖动**：按住小人拖，应该跟着走。borderless 窗口的拖拽是自己实现的，
   这是最容易出问题的一处。
5. **确认能退出**：菜单栏 →「退出桌面宠物」。**如果菜单项是灰的**，说明
   `NSMenuItem` 的 `target` 没生效。
6. ~~最后验打包~~ → ✅ **CI 已验**（含从 zip 解包后重验签名那步）。
7. ~~才轮到 Actions~~ → ✅ **CI 本身已跑通**（手工 `workflow_dispatch`）。
   ⚠️ 但**当时没打 tag**，而 `挂到 GitHub Release` 那一步只在 tag 触发时才执行 ——
   所以**它到现在一次都没跑过**。等你在 Mac 上验过 2~5 步、打第一个 tag 时，
   这条才算真的走完。

> 心里有数：**从第 2 步开始每一步都可能失败**，见下面「我（作者）最可能写错的地方」。

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
│   └── Info.plist                    app bundle 元数据；LSUIElement 在这里
├── Sources/DesktopPet/
│   ├── main.swift                    入口。必须叫 main.swift
│   ├── AppDelegate.swift             装配窗口 + 菜单栏
│   ├── PetWindow.swift               透明/置顶/可拖拽的 NSWindow 子类
│   ├── PetView.swift                 用 NSBezierPath 画小人 + 定时器动画
│   └── StatusItem.swift              菜单栏「退出」
├── scripts/
│   └── build.sh                      组 .app → 签名 → 用 ditto 打包
└── .github/workflows/
    └── build.yml                     macos-15 上构建 + 发 Release
```

---

## 在 Mac 上开发

```sh
swift build          # 编译
swift run            # 直接跑（能看到小人和菜单栏图标）

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

---

## 已知限制

- **别人进入全屏应用时，小人可能看不见**，即使设了 `.fullScreenAuxiliary`。
  这是 Apple 论坛上反复出现的问题，没有可靠解法。
- **没有代码签名**（没买 Apple 开发者账号）。每次给别人都要过一遍 Gatekeeper。
- **只在 macOS 13+ 上跑**（`Package.swift` 的 `.macOS(.v13)` 和 `Info.plist` 的
  `LSMinimumSystemVersion`，改一个就得改另一个）。
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
