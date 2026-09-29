# 拂晓 DAWNUS · 原生 iOS 闹钟

一个用 **SwiftUI + AlarmKit** 写的原生 iOS 闹钟 App。

上一版是 HTML 原型（`../Dawnus闹钟.html`），这一版是能在 Xcode 里打开、能装进 iPhone、能用系统级闹钟真把你叫醒的工程代码。

> 核心命题没变：**真正的失败从来不是没听见，是听见了没起来。**
> 所以闹钟只负责「响」，拂晓负责「起」。

---

## 快速开始

```bash
cd Dawnus
open Dawnus.xcodeproj      # 或者双击
```

在 Xcode 里选 **Dawnus** scheme → 目标设备选 iPhone 模拟器或真机 → ⌘R。

命令行也可以：

```bash
# 编译
xcodebuild -project Dawnus.xcodeproj -scheme Dawnus \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# 跑测试（13 个单元测试）
xcodebuild test -project Dawnus.xcodeproj -scheme Dawnus \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

### 要求

| 项 | 版本 | 说明 |
|---|---|---|
| Xcode | **26 及以上** | AlarmKit 是 iOS 26 才有的框架 |
| 部署目标 | iOS 26.0 | 已在 `project.yml` 里设好 |
| 真机（可选） | iPhone 11 及以上 | 想在锁屏/灵动岛看到闹钟必须真机 |
| 工程生成 | [XcodeGen](https://github.com/yonaskolb/XcodeGen) | 改了 `project.yml` 后跑 `xcodegen generate` |

`Dawnus.xcodeproj` 已经生成好了，不装 XcodeGen 也能直接打开。只有在你增删文件后才需要重新生成。

---

## 为什么这一版和 HTML 原型不一样

HTML 原型里闹钟是「定时器 + 全屏页面」。原生版本换掉了三个地基：

1. **AlarmKit 真闹钟**。iOS 26 首次对外开放系统闹钟能力。它能突破静音开关和专注模式，出现在锁屏、灵动岛、StandBy 和配对的 Apple Watch 上——这些以前只有系统自带时钟能做到。
2. **preAlert 渐醒窗口**。AlarmKit 允许你把「响铃前的那段时间」也纳入调度。拂晓把它做成晨曦：屏幕从深夜蓝推到晨金色，让皮质醇先一步上涌。
3. **系统 UI 上直接带按钮**。闹钟在锁屏上就有「起床」和「贪睡 ¥128」两个按钮，点贪睡会把你拉进 App 的全屏解锁流程，同时代价已经涨价。

---

## 五个创意模块 → 对应代码

| 模块 | 做什么 | 代码位置 |
|---|---|---|
| **双环径向拨盘** | 外环调小时、内环调分钟，单指沿弧拖动，抬手吸附刻度 | `Dawnus/UI/DialPicker.swift` |
| **代价模式 Stake** | 承诺金额 + 惩罚去向，贪睡一次 ×1.6 递增 | `WakeBrain.penalty` / `UI/AlarmEditorView.swift` |
| **晨曦渐醒** | 响前 20 分钟天空推进；同步成 AlarmKit 的 preAlert | `UI/Theme.swift` (`DawnSky`) / `Engine/AlarmEngine.swift` |
| **晨间仪式链** | 关掉闹钟后的 3 个微任务，全勾才算起床成功 | `UI/RitualView.swift` |
| **连环递增** | 第 1 响 1 题、第 2 响 2 题、第 3 响 3 题，没有回头路 | `WakeDifficulty.requiredSolves` / `UI/RingingView.swift` |

---

## 工程结构

```
Dawnus/
├── project.yml                     # XcodeGen 工程描述（改这里，不要手改 xcodeproj）
├── Dawnus/                         # 主 App
│   ├── DawnusApp.swift             # 入口：授权、同步闹钟、接管系统按钮回调
│   ├── Info.plist                  # 含 NSAlarmKitUsageDescription（缺了就无法调度闹钟）
│   ├── Model/
│   │   ├── DawnusAlarm.swift       # 闹钟 / 难度 / 代价 / 仪式链 / 账本
│   │   ├── DawnusMetadata.swift    # 跨进程传给实时活动的元数据
│   │   └── Notifications.swift
│   ├── Store/AlarmStore.swift      # JSON 持久化 + 结算 + 损坏恢复
│   ├── Engine/
│   │   ├── AlarmEngine.swift       # AlarmKit 封装（本项目的核心）
│   │   ├── WakeBrain.swift         # 出题 / 涨价 / 统计，纯函数
│   │   └── WakeSound.swift         # 渐醒铃声播放
│   ├── Intents/DawnusIntents.swift # 系统闹钟按钮 → App 的桥
│   ├── UI/                         # RootView / 列表 / 拨盘 / 编辑器 / 响铃 / 仪式链 / 数据 / 引擎
│   └── Resources/
│       ├── dawn.caf                # 程序生成的和弦铃声（12 秒，呼吸式包络）
│       └── Assets.xcassets         # App 图标（程序生成的日出）
├── DawnusWidget/                   # 实时活动扩展：锁屏 / 灵动岛 / StandBy
├── DawnusTests/                    # 13 个单元测试
└── screenshots/                    # 模拟器实拍
```

---

## AlarmKit 集成要点（踩过的坑都在这）

```swift
// 1. Info.plist 必须有这个键，否则根本调度不了闹钟
NSAlarmKitUsageDescription

// 2. 渐醒 = preAlert；postAlert 是响铃后的宽限时间
let countdown = Alarm.CountdownDuration(
    preAlert: TimeInterval(alarm.dawnMinutes * 60),
    postAlert: TimeInterval(...)
)

// 3. 只要用了 countdown，就必须同时提供 countdown 和 paused 两种呈现，
//    否则系统会直接解除闹钟。并且必须有 widget extension 渲染它。
AlarmPresentation(alert:countdown:paused:)

// 4. secondaryButtonBehavior = .custom + openAppWhenRun = true
//    才能让「贪睡」按钮把 App 拉到前台进全屏解锁
```

几个容易踩的：

- **`.pauseButton` / `.resumeButton` 这些静态成员在 iOS 26 SDK 里不存在**，得自己 `AlarmButton(text:textColor:systemImageName:)`。
- **`AlarmConfiguration` 的真实类型是 `AlarmManager.AlarmConfiguration`**，直接写短名在部分上下文里推断不出来。
- **`AlarmAttributes.metadata` 是可选值**，实时活动里必须兜底，否则整个 live activity 渲染不出来。
- **链接的是 `Charts.framework`，不是 `SwiftCharts.framework`**（这个坑在链接期才报错）。
- **`AlarmManager` / `alarmUpdates` 还没做好 Sendable 标注**，用 `@preconcurrency import AlarmKit` 引进来最省事。
- **模拟器上闹钟不会真响**（`.default` 声音在模拟器上是哑的）。要验证真响，装到真机，并且真机需要配置 App Group 的签名 team。

---

## 演示模式（截图/讲方案用）

不想一步步点？直接落到指定界面：

```bash
# 直接进全屏响铃与解锁
xcrun simctl launch booted com.dawnus.app -dawnus-demo ring

# 直接进晨间仪式链
xcrun simctl launch booted com.dawnus.app -dawnus-demo ritual

# 直接进数据页
xcrun simctl launch booted com.dawnus.app -dawnus-demo stats
```

演示模式下不会弹权限请求，画面干净。App 内「引擎」Tab 里也有四个按钮，一键触发四种难度的完整链路。

另外，为了在几十秒内能走完整条链路，App 内「贪睡」用的是 **20 秒**而不是真实的 9 分钟——改在 `RingingView.snooze()` 一行里。

---

## 验证情况

- **编译**：App target + Widget Extension target 全部通过（Xcode 26.6 / iOS 26.5 SDK）。
- **单元测试**：13 个测试全绿，覆盖出题正确性与选项唯一性、代价涨价序列（¥80→128→205→328→524）、连环题数递增与封顶、起床率、连续打卡的中断与延续、下一次响铃时间、元数据跨进程序列化。
- **真机运行**：已装进 iPhone 17 Pro 模拟器实跑，四个界面截图见 `screenshots/`。系统原生弹出了「要允许『拂晓』安排闹钟和计时器吗？」，说明 AlarmKit 授权链路真的接上了。
- **过程中修掉的真实问题**：
  - 存档解码失败时被静默覆盖 → 现在会先备份成 `*.damaged-<时间>.json` 再重建，并在「引擎」页告知用户。
  - 重复日文案输出「周一 三 六」→ 改成「周一 周三 周六」。
  - 启动时连弹两个权限弹窗 → 通知权限改到真正用到兜底路径时再申请。

---

## 装到真机

完整步骤见 **[真机安装指南.md](真机安装指南.md)**。最快路径：

```bash
./scripts/install-device.sh
```

它会自动找设备、查 iOS 版本、取签名 Team ID、生成不冲突的 bundle id，然后编译并安装。
前置条件只有两个：iPhone 升到 **iOS 26+**（AlarmKit 的硬要求）、Mac 上的 Xcode 登录了 Apple ID。

> 顺带一提：`com.apple.developer.alarmkit` 这个 entitlement **不存在**，是 LLM 编造的。
> AlarmKit 只需要在 Info.plist 里放 `NSAlarmKitUsageDescription`，本工程已放好。

---

## 已知限制

- **模拟器不响铃、没有灵动岛**，这些必须在真机验证。
- **App Group 默认关闭**。它属于受限 capability，免费个人 Apple ID 签不出来，留着会直接导致签名失败。代码已做双通道降级（见 `Dawnus/Store/SharedStore.swift`）：没有 App Group 时自动改用进程内 `UserDefaults`，实时活动的数据本来就靠 `AlarmAttributes` 下发，因此功能无损。付费账号可用 `./scripts/install-device.sh --app-group` 启用真正的跨进程共享。
- **代价模式的扣款是本地账本**，没有接真实支付。接支付要过 IAP 或走第三方，且涉及合规，这里刻意留在账本层面。
- 数据存储是 JSON 单文件，量级小、够用；要上生产建议换 SwiftData（模型层已经 Codable，迁移成本低）。
