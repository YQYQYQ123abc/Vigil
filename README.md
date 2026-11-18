# 警惕 / Vigil

保护你自己电脑上原有位置的重要文件。你选择已经在用的目录，继续用 Finder 和原来的应用工作；正常使用时保持安静，出现受保护的操作、保护中断或疑似换人时，按实际能力拦截、记录或提醒。

Protecting the important files you keep where they already are. Pick folders you already use, keep working in Finder — Vigil stays quiet until a protected action happens.

**官网 / Website:** https://yqyqyq123abc.github.io/Vigil/

## 当前状态 / Status

开发预览。iOS 与 macOS 已有共享 SwiftUI 四 Tab 原型，两个目标的 Debug 无签名构建已通过；真实目录持久化、系统扩展、身份验证与跨设备能力仍在开发。界面中的设备、保护状态与事件目前为示例数据。

Development preview. A shared SwiftUI four-tab prototype builds unsigned for iOS and macOS. Real folder persistence, the system extension, authentication, and cross-device features are still in progress.

## 仓库结构 / Layout

```
Vigil/                 iOS target (SwiftUI app entry, assets)
Vigil-macOS/           macOS target (app entry, folder picker, folder access)
VigilShared/           Shared models and views used by both targets
VigilTests/            Unit tests
Vigil.xcodeproj/       Xcode project (Xcode 26 .xcproj format)
icon/                  Icon design sources
docs/                  Marketing site, served by GitHub Pages
Vigil-Project-Plan.md  Product plan, platform order, and acceptance criteria
```

## 产品边界 / Boundaries

- 只在你选中的目录里工作，不监控整个系统。
- 事件与证据默认保存在本机，不上传文件内容。
- 没有账号依赖、广告和遥测。
- 不在你不知情时录屏或打开摄像头。
- 不承诺做不到的拦截：已打开的文件、已进入应用内存的内容会如实记录结果。

## 官网维护 / Site

站点在 `docs/`，由 GitHub Pages 从 `main` 分支的 `/docs` 发布，纯静态（`index.html` + `style.css` + `script.js`），无构建步骤。

- 中英切换：页面右上角按钮，或 `?lang=en` / `?lang=zh`。
- 联系邮箱：`docs/index.html` 中 `mailto:` 与页脚各一处，**上架前请替换为实际收信邮箱**。
- 本地预览：`python3 -m http.server 8000 --directory docs`，然后打开 http://127.0.0.1:8000/ 。

## 联系 / Contact

- 邮箱 / Email: 待填写（please replace `contact@example.com`）
- GitHub: https://github.com/YQYQYQ123abc
