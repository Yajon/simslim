# simslim

[中文](README.zh-CN.md) | [English](README.md)

通过关闭模拟器不需要的后台守护进程，在一台 Mac 上运行更多 iOS、Apple TV（tvOS）、Apple Watch（watchOS）和 Apple Vision Pro（visionOS）模拟器。

一个新启动的 iOS 模拟器会拉起大约 180 个后台服务：Siri、Spotlight 索引、照片分析、News、锁屏壁纸、iCloud 同步等等。在你用模拟器做开发、测试或 CI 时，这些都不重要。simslim 会把这些服务关掉，让每个模拟器的内存大约降到原来的 1/4。同一台笔记本上，你就能从只能跑几个模拟器变成铺满一屏。

https://github.com/user-attachments/assets/f4665e41-43b4-49cd-9388-3da533e9fd7b

_在一台 16 GB 的 M1 Pro 上同时运行 12 个瘦身模拟器，每个由各自的 Claude Code agent 通过 MobAI 驱动。原生模拟器在大约 5 个时就开始卡顿了。_

# 本分支的适配（相对上游 main）

- **低版本 Xcode**：Swift 源码可在 Xcode 15.1 / Swift 5.9 下用 `swiftc -warnings-as-errors` 编译；并发批处理里跨 `await` 修改 actor 隔离属性的写法已改为同步辅助方法。CI 仍使用 Xcode 26.6。
- **最低系统版本**：应用可运行于 macOS 13 及以上（`gui/Info.plist` 的 `LSMinimumSystemVersion` 与 `scripts/build-app.sh` 的 `MACOS_DEPLOYMENT_TARGET` 同为 13.0）；macOS 14+ 的 SwiftUI 类型通过 `#available` 回退兼容。
- **中英文切换**：工具栏 Language 菜单可在 English / 简体中文之间切换，选择会被保存并在重启应用后生效；所有界面文案经 `tr()` 查找 `gui/zh-Hans.lproj/Localizable.strings`。
- **多架构打包**：`ARCHS` 支持 arm64 / x86_64 / universal / all，产物含通用包与按架构的精简包。
- **多平台运行时**：`--preserve-boot-state` 与 `--no-reboot` 的选择按 CLI 的版本门槛判断（iOS/tvOS 18.5、watchOS 11.5、visionOS 2.5 及以上）。

## 数据

同一个模拟器，分别以原生状态和瘦身状态启动，设备与静置时间相同（M1 Pro，16 GB）：

|        | 原生   | 瘦身   |
| ------ | ------ | ------ |
| 进程数 | 258    | 70     |
| 内存   | 4.0 GB | 0.9 GB |

这里的内存是 `phys_footprint`，也就是活动监视器显示的数字，它计入了压缩和换出的内存页。这决定了机器开始换页之前能塞下多少个模拟器。运行 `simslim measure <udid>` 可以查看任意已启动模拟器的该项数据。

`status` 和 `measure` 回答的是不同的问题。`status` 只统计 SimSlim 管理的允许列表（allowlist）内的 launchd 标签，不是实时的进程计数。一个瘦身启动的模拟器仍然会运行必需的核心服务，以及系统应用和扩展。`measure` 会遍历该模拟器 `launchd_sim` 下的每一个进程并累加 `phys_footprint`。`ps` 的 RSS 值之和不可比，因为 RSS 会把共享内存映射对每个映射它的进程都计一次。

## 安装

```sh
brew install mobai-app/tap/simslim
```

或

```sh
go install github.com/mobai-app/simslim/cmd/simslim@latest
```

仅支持 macOS，并且需要装有 iOS、tvOS、watchOS 或 visionOS 模拟器运行时的 Xcode，因为 simslim 是通过 `xcrun simctl` 来驱动模拟器的。四种平台使用相同的命令和服务配置；`list`、`top` 和 macOS 应用会显示每个设备的平台，JSON 设备记录也包含 `platform` 与 `osVersion`。

macOS 应用最低支持 macOS 13，可用 Xcode 15.1（Swift 5.9）或更新版本构建；CI 使用 Xcode 26.6。

## macOS 应用

这个 SwiftUI 应用内嵌了 CLI，并额外提供：

- 可搜索的模拟器状态、磁盘占用和实时内存（RAM）列。
- 可搜索的服务配置，含逐个守护进程的控制与用途说明。
- 只读的磁盘分析，加上对允许列表内数据的确认式清理。
- 克隆、重命名、抹除、删除，以及 Finder 快捷入口。
- 工具栏 Language 菜单切换 English / 简体中文，重启应用后生效。

应用最低支持 macOS 13（Info.plist 与构建脚本的部署目标一致），并已在 Xcode 15.1 / Swift 5.9 下验证编译。

用 Go 和 Xcode 本地构建：

```sh
make app                       # 当前机器的架构
make app ARCHS=arm64,x86_64    # 通用包（两种架构）
make app ARCHS=arm64           # 单一架构
make app ARCHS=all             # 通用包 + 每种架构一个独立包
open build/SimSlim.app
```

`ARCHS` 接受 `arm64` 和/或 `x86_64`（用逗号或空格分隔），或 `universal` 作为两者的简写。应用本身和内置的 `simslim` CLI 都会针对每个请求的架构编译，并用 lipo 合并进同一个二进制；不传 `ARCHS` 时只构建运行构建的那台机器的架构。

`ARCHS=all` 还会在主包旁边额外写出每种架构的精简包，于是一次构建会产出 `build/SimSlim.app`（通用包）以及 `build/SimSlim-arm64.app` 和 `build/SimSlim-x86_64.app`。推送 `v*` 标签会把找到的每个包压缩，连同 CLI 压缩包和 Homebrew bottle 一起发布到一个 GitHub Release。

内存估算只是参考，并非可叠加的节省；详见[测量方法](docs/category-memory.md)。SimSlim 建议在进行服务或磁盘改动前先克隆，以便副本可以作为备份。

## 用法

```sh
simslim list             # 模拟器及其瘦身状态（加 --booted 可筛选）
simslim profiles         # 瘦身启动会关掉什么
simslim profiles <id>    # 某类别下的 launchd 标签
simslim on <udid>        # 瘦身一个模拟器并重启为瘦身状态
simslim on <udid> --no-reboot   # 仅对当前启动会话瘦身，不重启
simslim off <udid>       # 还原为原生状态
simslim enable <udid> icloud,photos   # 不重启，立即恢复服务
simslim disable <udid> icloud         # 不重启，再次关闭
simslim status <udid>    # 受管理的 launchd 标签状态（不是进程计数）
simslim verify <udid> --profile ci.json   # 精确匹配配置；有偏差时返回非零
simslim doctor <udid> --requires push,storekit,universal-links
simslim measure <udid>   # 已启动模拟器的内存占用
simslim top              # 实时机群监视；进入某个模拟器查看每个守护进程的内存/CPU
simslim size <udid>      # 模拟器分配的总大小
simslim disk-plan <udid> # 测量可回收数据；只读
simslim disk-clean --categories caches,logs --confirm <udid>
simslim clone <udid> <name>
simslim repair-clone <source-udid> <clone-udid>
simslim rename <udid> <name>
simslim boot <udid>      # 启动模拟器并等待其服务就绪
simslim shutdown <udid>  # 关闭已启动的模拟器
simslim erase <udid>     # 抹除应用、数据、设置以及瘦身覆盖项
simslim delete <udid>    # 永久删除一个模拟器
simslim watch --profile dev.json      # 持续瘦身新模拟器，直到 Ctrl-C
```

只读命令、模拟器管理类命令以及 `enable`、`disable` 都支持 `--json`，便于集成和 macOS 应用使用。

保留你确实需要的某个类别，比如 Spotlight 搜索：

```sh
simslim on <udid> --except search
```

或者只保留某个具体的守护进程，比如推送通知：

```sh
simslim on <udid> --keep com.apple.apsd
```

<details>
<summary>所有瘦身类别</summary>

| ID             | 类别                   | 关闭内容                                               | ~MB |
| -------------- | ---------------------- | ------------------------------------------------------ | --- |
| `widgets`      | 小组件与壁纸           | 主屏与锁屏壁纸、小组件和实时活动。                     | 675 |
| `siri`         | Siri 与智能            | Siri、Apple Intelligence、语音以及设备端 ML 模型服务。 | 265 |
| `search`       | Spotlight 与搜索       | 设备端 Spotlight 与设置内搜索服务。                    | 50  |
| `icloud`       | iCloud 与 Apple 账户   | iCloud 同步、Apple 账户、钥匙串和备份服务。            | 100 |
| `store`        | App Store、推送与媒体  | App Store、推送通知、StoreKit 和媒体服务。             | 80  |
| `pim`          | 邮件、日历与通讯录     | 邮件、日历、通讯录、提醒事项及相关同步服务。           | 80  |
| `web`          | Safari 同步与网络服务  | Safari 同步、Web 推送、隐私和通用链接服务。            | 50  |
| `family`       | 家庭与屏幕使用时间     | 家人共享、屏幕使用时间和使用统计。                     | 65  |
| `health`       | 健康、家庭与健身       | HealthKit、HomeKit 和健身服务。                        | 135 |
| `photos`       | 照片与媒体分析         | 照片图库、照片分析和媒体分析服务。                     | 60  |
| `apps`         | News、天气、地图与游戏 | News、天气、地图、提示和游戏服务。                     | 90  |
| `messaging`    | 信息与 FaceTime        | iMessage、FaceTime、通话和身份服务。                   | 60  |
| `connectivity` | 共享与设备互联         | AirDrop、连续互通、CarPlay、Watch 和 查找 服务。       | 65  |
| `telemetry`    | 广告、诊断与遥测       | DeviceCheck、广告隐私、分析、诊断和反馈服务。          | 105 |
| `mdm`          | 设备管理               | 声明式设备管理与受管理资源服务。                       | 10  |
| `other`        | 其它后台服务           | 钱包、App Clips、商务服务、资源及其它杂项后台守护进程。 | 225 |

内存数字为 iOS 26.5 干净启动的中位数，不可叠加；详见[测量方法](docs/category-memory.md)。运行 `simslim profiles <id>` 可查看某类别下的守护进程。

</details>

### CI 运行器较慢时

`simslim on` 会启动模拟器，以每次一个 `launchctl` 调用的方式关闭约 170 个守护进程，然后重启——整个过程都在单个 10 分钟时限内完成。共享的 CI 运行器（例如 GitHub 托管的 macOS 运行器）更慢且更不可预测，可能在重新配置到一半时超时，报出 `context deadline exceeded` 错误。可以用全局 `--boot-timeout` 标志或 `SIMSLIM_BOOT_TIMEOUT` 环境变量来调高它：

```sh
simslim on <udid> --boot-timeout 15m
# 或针对整个任务：
export SIMSLIM_BOOT_TIMEOUT=15m
```

每次单独的 `launchctl` 切换也有各自 2 分钟的超时，冷启动后最早的几次切换在慢速宿主机上可能超过这一限制（失败的会自动重试）。可以用全局 `--spawn-timeout` 标志或 `SIMSLIM_SPAWN_TIMEOUT` 环境变量来调高：

```sh
simslim on <udid> --spawn-timeout 5m
# 或针对整个任务：
export SIMSLIM_SPAWN_TIMEOUT=5m
```

### 配置文件

为了可重复的设定，你可以把一个 JSON 配置文件随项目一起提交，并在每次运行时应用。一个 `ci.json` 和一个 `dev.json` 可以针对不同用途做出不同的瘦身：

```json
{
  "name": "ci",
  "description": "UI 测试运行",
  "except": ["search", "store"],
  "keep": ["com.apple.apsd"]
}
```

```sh
simslim on <udid> --profile ci.json
```

`except` 和 `keep` 对应于同名的命令行标志；`name` 和 `description` 是给读文件的人看的。未知字段、未知的类别 ID，以及不被任何类别关闭的标签都会被拒绝，因此拼写错误会直接报错。`--profile` 是其运行过程的唯一权威来源，不能和 `--except` 或 `--keep` 一起使用。

要交互式地创建一个，运行 `simslim profile ci.json`：先命名，然后用方向键和空格勾选要保留启用的整组功能，或按 `→` 展开某组功能、在其中保留单独的守护进程。指向一个目录会把 `<name>.json` 保存到那里，省略路径则打印到标准输出。

### 用 doctor 检查模拟器

瘦身模拟器是有意为之地把功能关掉，所以一个需要其中某项功能的测试套件，希望有一种快速方式能在运行前抓出被错误瘦身的模拟器。`doctor` 会对照你点名的功能检查一个已启动的模拟器，任意功能损坏便以非零退出，因此它天然适合作为 CI 的前置检查：

```sh
simslim doctor <udid> --requires push,storekit,universal-links
```

```
<udid>: 2/3 required features OK
  ok     push
  ok     universal-links
  BROKEN storekit — com.apple.storekitd disabled
```

功能 ID 比瘦身类别更细粒度：每个功能只映射到支撑某一能力的一组守护进程。运行 `simslim doctor --list` 可查看全部。检查和列表都支持 `--json`。

### 验证配置是否仍然生效

关闭覆盖项是每个模拟器各自的状态，很容易在不知不觉中丢失：被删除又重建的设备，或来自新运行时的模拟器，都会以原生状态启动；而当这种情况发生时，其它地方都不会大声报错——模拟器只是悄悄又变重了。`verify` 会把一个已启动模拟器的覆盖项与一份配置（即你传给 `on` 的同一个 `--profile`/`--except`/`--keep`）做比较，并在出现偏差时以非零退出，列出差异，这样脚本或 CI 步骤就能捕获它并重新运行 `simslim on`（幂等：只应用缺失的差异项）来修复：

```sh
simslim verify <udid> --profile ci.json || simslim on <udid> --profile ci.json
```

`doctor` 回答的是「我的测试需要的功能还能用吗？」，而 `verify` 回答的是「这个模拟器是否处于我配置的精确瘦身状态？」。支持 `--json`。

### 不重启式瘦身

`simslim on --no-reboot` 就地对正在运行的启动会话进行瘦身：它关闭每个守护进程，然后把它从 launchd 中剔除，于是进程立即停止且无法重生，没有关机/启动循环。它接受与 `on` 相同的 `--profile`/`--except`/`--keep` 选择。

```sh
simslim on <udid> --no-reboot --profile ci.json
```

在 iOS/tvOS 18.5、watchOS 11.5、visionOS 2.5 及更新版本上，覆盖项同样被持久化，所以下次启动也会以瘦身状态起来。更早的运行时无法持久化覆盖项，这是唯一能瘦身的方式，且状态在下次重启时丢失：每次启动后都要重新运行。当 `status` 读到一个这样的模拟器时会说明这一点，`status --json` 也会带上一个 `persistent` 字段。

实时瘦身只朝「更被关闭」的方向移动。已经被关闭到配置之外的受管理守护进程会原样保留，因为要实时重新启动一个守护进程需要逐标签的 bootstrap；可用 `enable` 不重启地恢复，或用 `simslim off` 通过重启恢复。

### 不重启地重新启用服务

瘦身后的模拟器有时需要临时恢复某个功能（例如同步测试要用 iCloud、选择器要用照片）。`enable` 会在运行中的模拟器里立即恢复指定类别或守护进程，`disable` 再关回去，两者都不重启、也不改动配置本身。

```sh
simslim enable <udid> icloud,photos       # 也可写：simslim enable <udid> icloud com.apple.apsd
simslim doctor <udid> --requires icloud   # 立即变为可用
simslim disable <udid> icloud             # 再次关闭，仍不重启
```

需要已启动的模拟器。`--json` 会用 `notStarted` 列出那些已被 launchd 重新启用、但要下次启动才会加载的守护进程，用 `stillEnabled` 列出 `disable` 特意保留运行的服务。要让改动持久化，加 `--save <profile.json>`：命令会把类别写进文件的 `except`（守护进程写进 `keep`），或从中移除，之后 `on`、`watch`、`verify` 都会与新配置一致。

```sh
simslim enable <udid> icloud --save dev.json   # 立即生效，并写入 dev.json
simslim watch --profile dev.json               # 每次启动都保留 iCloud
```

### 自动瘦身每一个新模拟器

`simslim watch` 不需要为每台设备单独执行命令。对于处于关机状态、且运行时能持久化覆盖项（iOS/tvOS 18.5、watchOS 11.5、visionOS 2.5 或更新）的模拟器，watch 会在它启动前把配置写入禁用覆盖项，因此首次启动就不会拉起这些守护进程。它用 kqueue 跟踪设备集目录，在 `simctl create` 后几毫秒内从 `device.plist` 播种新设备；已经启动的模拟器则在启动时以不重启方式瘦身。`xcodebuild` 并行测试创建的克隆体也由此覆盖。

```sh
simslim watch --except web,store &
xcodebuild test -scheme App -parallel-testing-enabled YES -parallel-testing-worker-count 4 ...
```

它接受与 `on` 相同的 `--profile` / `--except` / `--keep`，默认扫描 `default` 与 `testing` 设备集，可用 `--set` 指定其它设备集，运行到 Ctrl-C 为止。

## 磁盘清理

磁盘清理是永久性的，且与服务瘦身相互独立。`disk-plan` 是只读的。`disk-clean` 会关闭确切的那个模拟器，只清理允许列表内的按设备目录，且在没有 `--confirm` 时拒绝运行。

```sh
simslim disk-categories
simslim disk-plan <udid>
simslim disk-clean --categories caches,logs,temporary --confirm <udid>
# 可选：同时移除按需加载的语言模型
simslim disk-clean --categories linguistic-data --confirm <udid>
```

内建应用和核心 OS 的语言资源属于一份已签名的 iOS 运行时，由使用该版本的所有模拟器共享，因此 simslim 从不修改它们。必需的 Siri 资源被纳入测量只是因为 iOS 会在启动时恢复它们；按需语言数据是可选加入的，需要时有可能会再次下载。

`disk-plan` 还会报告一个只读的存储明细，涵盖已安装的应用包、Documents、应用数据和用户媒体。这些持久性行永远不在清理之列。详见[磁盘清理安全模型](docs/disk-cleanup.md)了解恢复行为、保障措施以及 Xcode 26.6 的验证结果。

## 作为 Go 库使用

仓库根目录是一个可导入的包，且无外部依赖，因此你可以从自己的工具中直接驱动模拟器，而不必调用 CLI：

```sh
go get github.com/mobai-app/simslim
```

```go
package main

import (
	"context"
	"fmt"

	"github.com/mobai-app/simslim"
)

func main() {
	ctx := context.Background()

	devices, err := simslim.ListDevices(ctx)
	if err != nil {
		panic(err)
	}

	// 瘦身每个已启动的模拟器，保留 Siri 和搜索启用。
	profile, err := simslim.BuildProfile("", "siri,search", "")
	if err != nil {
		panic(err)
	}
	for _, d := range devices {
		if d.State != "Booted" {
			continue
		}
		changed, err := simslim.EnableSlim(ctx, d.Set, d.UDID, profile, func(msg string) {
			fmt.Println(d.UDID, msg)
		})
		fmt.Println(d.UDID, "changed:", changed, "err:", err)
	}
}
```

这个包从不向 stdout 写入——它返回值，并通过你传入的 `simslim.Reporter` 回调来汇报进度。`simslim.Categories`、`simslim.Features` 和 `simslim.SlimmableSet()` 暴露的是与 CLI 完全相同的允许列表；`simslim.EnableServices`、`simslim.DisableServices` 和 `simslim.SaveServices` 分别支撑 `enable`、`disable` 与 `--save`。仅支持 macOS，因为所有操作都通过 `xcrun simctl` 执行。

## 工作原理

`simslim on` 会把所选 launchd 标签的持久化 `launchctl disable` 条目写入模拟器自己的 launchd 数据库，然后重启它。这些条目在重启后依然生效，因此模拟器从此只需一次启动就会以瘦身状态起来。`simslim off` 清除它们并重启回原生状态。你的 Mac 永远不会被触碰，只动你指定的那个模拟器，且只动那些可以安全关闭的服务。核心工作流服务（如 `sharingd`），以及少数一旦关闭会让模拟器卡死的服务，会被保留运行。

已验证可持久化的最早运行时是 iOS 18.5。iOS 17.x 和 18.3 会接受每次 `launchctl disable`，但模拟器在重启后会回到原生状态。持久化瘦身的版本门槛为 iOS/tvOS 18.5、watchOS 11.5 或 visionOS 2.5 及更新版本；tvOS、watchOS 与 visionOS 的门槛按对应的 iOS 代际推算，并非各自独立测量的最早持久化运行时。`simslim on` 在启动或改动 launchd 状态之前，会拒绝更早的运行时，并指向 `--no-reboot`（只瘦身当前启动会话，见[不重启式瘦身](#不重启式瘦身)）。每个平台在重启后仍会被读回，如果有任何请求的覆盖项丢失，命令会失败而不是谎报成功。`off` 在旧运行时依然可用。

这是每个模拟器各自的状态，而非全局设置。守护进程的关闭只发生在那一个模拟器的 launchd 数据库里，不会波及别处。`simslim clone` 会连同已安装的应用、应用数据和设置一起，复制源模拟器精确的 SimSlim 受管理配置。它还会重定位模拟器本地的符号链接、重新生成应用注册数据库，并清理复制过来的系统缓存与临时文件。在结束前，它会启动克隆体并审计其运行进程，检查是否存在指向源的路径。克隆体随后关机，源模拟器恢复到克隆前的启动状态。

由较旧 SimSlim 构建版本创建的克隆，可以在不删除其已安装应用或应用数据的情况下就地修复：

```sh
simslim repair-clone <source-udid> <clone-udid>
```

修复会保留克隆体当前的 SimSlim 配置和启动状态。在重建被复制的路径期间，源模拟器保持关机；如果仍存在指向该源的直接链接或打开的文件，克隆体会保持关机而非被重新启动。CoreSimulator 不暴露克隆血缘关系，因此请传入确切的源 UDID：SimSlim 会校验对你所指定源的引用。

`erase`、删除后重建，以及「抹掉所有内容和设置」依然会产生原生服务状态，于是模拟器的内存会重新攀升，直到你重新运行 `simslim on`。从一个新的或更新过的运行时创建的模拟器也会以原生状态启动。tar 或文件系统快照同样会保留该配置。运行 `simslim list` 查看当前状态，或用 `simslim verify` 对照某份具体配置检查。

## 你会失去什么

关闭服务对大多数开发、UI 自动化和 CI 都没问题，但有些功能确实会停止工作。值得知道的几点：

- Spotlight 和设置内搜索会无结果返回（`search`）。
- 没有 `searchd` 时，文件应用与文稿选择器的「最近项目」显示「内容不可用」（`search`）。
- 推送通知需要 `apsd`，StoreKit 测试需要 `storekitd`（`store`）。
- 通用链接需要 `swcd`（`web`）。
- 声明式设备管理，以及依赖它的 MDM / 配置描述文件工作流需要 `mdm`。
- App Clips 需要 `clipserviced`，VoiceOver 语音等无障碍资源下载需要 `axassetsd`（`other`）。
- 通讯录、照片和日历选择器在缺少对应类别时可能会出问题。

`simslim profiles` 会列出每个类别，因此你可以用 `--except` 保留某个类别，或用 `--keep` 保留单独的守护进程。

## 为什么

测试正在发生转变。一旦 agent 开始写应用，你也会希望让 agent 去运行它们，而 iOS 应用运行的地方就是模拟器。一个 agent，一个模拟器。因此你一次能完成多少工作，取决于一台机器能容纳多少个模拟器，而原生模拟器很重，笔记本很快就被填满。瘦身它们是抬高这个上限最便宜的方式：机器上的模拟器越多，就有越多 agent 在上面并行工作。

为 [MobAI](https://mobai.run) 而构建，以便在一台机器上运行更多模拟器。

## 许可证

MIT，版权归 Interlap 所有。
