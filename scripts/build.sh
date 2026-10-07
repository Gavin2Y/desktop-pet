#!/usr/bin/env bash
#
# 把 SPM 编译出来的裸二进制组装成 DesktopPet.app，签名，打成 zip。
# 本地 Mac 和 GitHub 的 macOS runner 通用。
#
#   bash scripts/build.sh                        # universal（默认）
#   ARCHS=arm64 bash scripts/build.sh            # 单架构回退
#   VERSION=1.2.3 BUILD_NUMBER=42 bash scripts/build.sh
#
# 产物落在 dist/：DesktopPet-<版本>.zip 和它的 .sha256。
#
# ⚠️ 在 Linux 上**跑不了**（没有 swift，也没有 codesign/ditto/PlistBuddy）。
#    这个脚本只能在 macOS 上执行。
set -euo pipefail

APP_NAME="DesktopPet"

VERSION="${VERSION:-0.0.1}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"

# ⚠️ ARCHS 是**这个脚本自己的**变量，不是 SwiftPM 的环境变量。
#    （网上流传的 `ARCHES=... swift build` 没有 Apple 官方来源，别用。）
#
#    默认出 universal，这样 Intel 和 Apple Silicon 的 Mac 都能跑。
#    但 universal 构建是**本仓库作者无法验证的额外变量**（没有 macOS 环境），
#    所以留了一个一字之差的回退：
#
#        ARCHS=arm64 bash scripts/build.sh
#
#    其余一个字都不用改 —— 产物路径是算出来的，没有硬编码。
ARCHS="${ARCHS:-arm64 x86_64}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
ZIP="$DIST/$APP_NAME-$VERSION.zip"

say() { printf '%s\n' "$*"; }
die() { printf '❌ %s\n' "$*" >&2; exit 1; }

say "══ 1/5 工具链 ══"
# 把工具链版本打进日志：CI 出问题时，答案通常就在这几行里。
sw_vers || true
xcodebuild -version || true
swift --version

# 构建参数和查询参数分开。
# ⚠️ 两者的差别**只有 --product**（它不影响 bin path）。这是刻意的：
#    --show-bin-path 要传「和构建时一样的参数」，而少一个不影响路径的
#    参数比多传一个更安全。
BUILD_ARGS=(--configuration release --product "$APP_NAME")
QUERY_ARGS=(--configuration release)

# 这里依赖 shell 的单词切分来遍历 "arm64 x86_64"，所以 $ARCHS 不能加引号。
# shellcheck disable=SC2086
for arch in $ARCHS; do
    BUILD_ARGS+=(--arch "$arch")
    QUERY_ARGS+=(--arch "$arch")
done

say
# ⚠️⚠️ **`${ARCHS}` 的花括号不能省。** 这里踩过一次真实的坑（CI run #1 就挂在这行）：
#    `$ARCHS` 后面紧跟全角括号 `）`，bash 会把那个多字节字符的**头一个字节**当成
#    变量名的一部分，于是去找一个叫 `ARCHS\xef` 的变量，在 `set -u` 下直接报
#    `ARCHS�: unbound variable`。**报错里那个乱码字符就是线索。**
#    规矩：凡是 `$变量` 后面紧跟中文标点（）、：，「」 的地方，一律写 `${变量}`。
say "══ 2/5 编译（架构：${ARCHS}）══"
swift build "${BUILD_ARGS[@]}"

# ⚠️⚠️ **绝不硬编码产物路径。**
#
#    记忆里的 `.build/apple/Products/Release/` 只在 universal 时成立；单架构
#    是 `.build/<triple>/...`。而且 SwiftPM 6.4 把默认构建后端从 native 换成了
#    Swift Build，单架构路径还多了一层 `Products/` —— 也就是说**这个路径已经
#    变过一次了**。硬编码的人会在某天毫无预兆地拿到 `No such file or directory`。
#
#    `--show-bin-path` 让 SwiftPM 自己说路径。官方 Release Notes 明确推荐
#    用它替代硬编码，并要求**传入和构建时完全一样的参数**。
#
#    `tail -n 1` 是防御性的：多个 --arch 时它返回一行还是多行，没有找到权威
#    说明，取最后一行两种情况都不会错。
BIN_DIR="$(swift build "${QUERY_ARGS[@]}" --show-bin-path | tail -n 1)"
BIN="$BIN_DIR/$APP_NAME"

if [ ! -f "$BIN" ]; then
    say "   ⚠️ --show-bin-path 给的路径不存在（${BIN}），在 .build 里搜一遍"
    BIN="$(find "$ROOT/.build" -type f -name "$APP_NAME" -perm -u+x -print \
        | sort | head -n 1 || true)"
fi

if [ -z "${BIN:-}" ] || [ ! -f "$BIN" ]; then
    say "   .build 里所有叫 $APP_NAME 的东西："
    find "$ROOT/.build" -maxdepth 5 -name "$APP_NAME" -print >&2 || true
    die "找不到编译出来的可执行文件"
fi

say "   可执行文件：$BIN"
lipo -archs "$BIN" 2>/dev/null || true

say
say "══ 3/5 组装 $APP_NAME.app ══"
# ⚠️⚠️ **这一段必须在签名之前全部做完。**
#
#    签名之后对 bundle 的**任何**改动 —— 改文件、加文件、删文件、改权限，
#    哪怕只是改一行版本号 —— 都会让签名失效。用户看到的报错是
#    「应用已损坏，无法打开」，而原因看起来跟"改了个版本号"毫无关系。
#
#    铁律：所有拷贝完成 → codesign → 只读不动 → 打包。
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
chmod +x "$APP/Contents/MacOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# 版本号注入。两个 key 都必须在 Info.plist 模板里**已经存在**，
# PlistBuddy 的 Set 才能生效。
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" \
    "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" \
    "$APP/Contents/Info.plist"

# 早失败好过晚失败：plist 语法错了在这里就停下，而不是等到用户打不开应用。
plutil -lint "$APP/Contents/Info.plist"

# 有图标就放进去 —— ⚠️ 必须在签名**之前**。
if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
    cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
    say "   图标：AppIcon.icns"
fi

say
say "══ 4/5 签名 ══"
# ad-hoc 签名（identity 就是那个 `-`）。
#
# ⚠️ 在 Apple Silicon 上这**不是可选项**：内核层的 AMFI 会直接杀掉完全未签名
#    的 Mach-O。ad-hoc 不需要任何证书、密钥或 keychain，就能满足内核这一层。
#
# ⚠️ 但它**满足不了 Gatekeeper**。用户首次打开仍会看到拦截，正确操作见 README
#    （**不是右键打开** —— 那在 macOS 15 上已经失效了）。
#
# ⚠️ 不要加 --deep。Apple 已明确不推荐它，而且这个 bundle 里没有嵌套代码，
#    用不上。
codesign --force --sign - "$APP"
codesign --verify --strict --verbose=2 "$APP"

say
say "══ 5/5 打包 ══"
rm -f "$ZIP"

# ⚠️⚠️ **必须用 ditto，不能用 `zip -r`。**
#
#    `zip` 不保留符号链接（除非加 -y）也不保留扩展属性，解压出来的 app 与
#    签名时的不一致，`codesign --verify` 会失败，用户看到
#    「应用已损坏，无法打开」或者
#    `code has no resources but signature indicates they must be present`。
#
#    -k            : 输出 PKZip 格式。**少了它产出的就不是 zip**，
#                    挂到 GitHub Release 上别人也解不开。
#    --keepParent  : 把 `DesktopPet.app/` 这一层也放进归档。**少了它解压出来
#                    文件会散架**，bundle 直接不存在了。
#
#    ⚠️ 不要加 --sequesterRsrc。网上到处是这个写法，但 Apple 的原话是它
#       "never the right option for app distribution" —— 它会把元数据挪到
#       __MACOSX/，对签名 bundle 恰恰是帮倒忙。
ditto -c -k --keepParent "$APP" "$ZIP"

say
say "══ 自检：从 zip 解出来，签名还成立吗 ══"
# 这一步是**故意的**：把「打包破坏了签名」这个失败模式在构建时当场抓住，
# 而不是等用户下载后报「应用已损坏」。
VERIFY_DIR="$(mktemp -d)"
trap 'rm -rf "$VERIFY_DIR"' EXIT
ditto -x -k "$ZIP" "$VERIFY_DIR"
codesign --verify --strict --verbose=2 "$VERIFY_DIR/$APP_NAME.app"
rm -rf "$VERIFY_DIR"
say "✅ zip 解包之后签名仍然成立"

say
shasum -a 256 "$ZIP" | tee "$ZIP.sha256"
ls -lh "$ZIP"
