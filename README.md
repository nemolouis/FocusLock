# FocusLock

一个原生 macOS 番茄钟，专注期间可以锁定指定的 App。SwiftUI + Swift Charts，无第三方依赖，数据只存在本机。

*A native macOS pomodoro timer that blocks chosen apps while you focus. Chinese and English UI, light and dark mode.*

需要 macOS 14 或更高版本。

## 功能

- **番茄钟**：倒计时（15/25/45/60 分钟预设或自定义 1–240 分钟）/ 正计时；开始、暂停、继续、结束（保存）、放弃（不保存）；空格键开始 / 暂停 / 跳过休息
- **自动休息**：每次专注保存后自动开始休息（默认 5 分钟，可在首页或「设置」里修改、关闭）；休息不记录、不锁定应用，可以跳过；结束时发通知，然后停下，不会自动开始下一个专注
- **锁定应用**：专注时，已经打开的锁定 App 会被要求退出；新打开的会被立即关闭，并弹回 FocusLock、发系统通知
  - 暂停时可选保持锁定
  - 严格模式：倒计时结束前不能暂停、结束、放弃或退出，也不能改锁定设置
- **分类**：在「专注」页直接选择；点「管理分类」可添加、改名、改颜色、拖动排序、删除
- **统计**：按日 / 周 / 月 / 年 / 总查看，可前后翻看以往周期；总时长、次数、完成番茄数、日均
  - 分类占比环形饼图、按小时 / 天 / 月堆叠的柱状图、近 16 周专注热力图（类似 GitHub 贡献图）并排一行
  - 热力图显示专注天数和最长连续天数，点某一天直接跳到那天的统计
- **专注记录**：在统计页下方，跟随所选周期；可按分类筛选（也可以点饼图图例）；可**补记**、**编辑**（分类、开始结束时间、备注、标签）和删除，编辑时会提示时间重叠
- **中英文 / 浅色深色**：在「设置」里切换。新安装默认跟随系统语言；从只有中文的旧版本升级时保持中文
- **菜单栏**：实时显示剩余时间，可直接暂停 / 继续 / 跳过休息；关掉窗口后照样计时和锁定
- 合盖睡眠时自动暂停；不足 1 分钟的专注不记录

## 构建

只需要 Xcode Command Line Tools（`xcode-select --install`），不需要完整 Xcode：

```bash
./build.sh            # 生成 build/FocusLock.app
./build.sh install    # 并复制到 /Applications（先从菜单栏退出正在运行的 FocusLock）
```

- 第一次构建会编译系统模块缓存，大约需要 1–2 分钟。
- 部分机器的 Command Line Tools 升级后会残留一个旧的 `module.modulemap`，导致 `redefinition of module 'SwiftBridging'`。`build.sh` 会用 VFS overlay 自动绕过，不改系统文件。
- 首次打开时建议允许通知，番茄完成、休息结束、拦截应用时都会提醒。

## 数据

- 保存在 `~/Library/Application Support/FocusLock/data.json`，「设置」页可以在访达中打开。
- 文件读取失败时会先备份成 `data.corrupt-时间戳.json`，不会直接覆盖。
- 设置环境变量 `FOCUSLOCK_DATA_DIR` 可以改用其他目录（测试用）。

## 代码结构

| 文件 | 内容 |
|---|---|
| `FocusLockApp.swift` | 入口、菜单栏、退出确认、外观切换 |
| `Models.swift` | 数据模型、中英文切换（`tr()`）、格式化 |
| `Store.swift` | 读写 JSON、分类 / 记录 / 黑名单的增删改 |
| `FocusTimer.swift` | 计时（专注、暂停、休息）和保存记录 |
| `AppBlocker.swift` | 监听 App 启动并关闭被锁定的应用 |
| `TimerView.swift` | 「专注」页 |
| `StatsView.swift`、`HeatmapView.swift`、`RecordsSection.swift`、`RecordEditor.swift` | 「统计」页：图表、热力图、记录列表、补记 / 编辑 |
| `BlocklistView.swift`、`CategoryManager.swift`、`SettingsView.swift` | 锁定应用、分类管理、设置 |

## 局限

- 锁定只在 FocusLock 运行时生效。强制退出 FocusLock（活动监视器）就能解除，自己给自己上锁本来就防不住管理员。
- 只能按 App 锁定，不能屏蔽网站。
- 分类名是用户自己的数据，切换语言时不会自动翻译。
