package main

import "github.com/mobai-app/simslim"

// tr returns the localized form of an English printf-style format string. Call
// it without arguments when the caller still owns the formatting (fmt.Printf,
// fmt.Sprintf, ...); the result is itself a format string, so placeholders must
// stay in the same order in every translation.
func tr(format string, arguments ...any) string {
	return simslim.TR(format, arguments...)
}

// trValue localizes a data string such as a category name, description or a
// short status label. It never touches identifiers used for comparisons.
func trValue(value string) string {
	return simslim.TRValue(value)
}

// Chinese backtick-free help text: a raw string cannot contain backticks, so
// inline command snippets use single quotes here.
const usageChinese = `simslim 通过停用模拟器不需要的后台守护进程，让同一台 Mac 能运行更多
iOS、tvOS、watchOS 和 visionOS 模拟器。

用法
  simslim <命令> [参数]

全局选项
  --set <名称|路径>    额外扫描这些设备集（逗号分隔）。默认设备集与 Xcode 的
                       'testing'（并行测试）设备集始终会被扫描；
                       用此选项添加自定义路径下的设备集。
  --boot-timeout 时长  启动并重新配置模拟器的最长耗时（默认 10m；
                       例如 '15m'）。CI 机器较慢时可增大。也可通过
                       SIMSLIM_BOOT_TIMEOUT 环境变量设置。
  --spawn-timeout 时长 模拟器内单次 launchctl 切换的最长耗时（默认 2m）。
                       首次启动繁忙、单个切换很慢时可增大。也可通过
                       SIMSLIM_SPAWN_TIMEOUT 环境变量设置。

命令
  list                 列出可用模拟器及其瘦身状态
      --booted         仅列出已启动的模拟器
  profiles [id]        显示瘦身启动会停用的守护进程类别；
                       传入类别 ID 可列出该类别的守护进程
  profile [路径]       交互式生成 --profile JSON 文件（写入路径或目录，
                       省略时输出到 stdout）
  on <udid>            为模拟器瘦身（持久化停用项 + 重启生效）
      --profile 路径   应用已提交的 JSON 配置（见下文）；与
                       --except/--keep 互斥
      --except ids     保持这些类别启用（逗号分隔）
      --keep labels    保持这些独立守护进程运行（逗号分隔）
      --no-reboot      不重启，在本次启动会话内停止守护进程。适用于所有
                       运行时，包括 iOS 17.x 与 18.3 —— 在那里这是唯一的
                       瘦身方式；下次重启后状态失效
      --preserve-boot-state
                       让最初处于关机状态的模拟器在完成后回到关机状态
  off <udid>           将模拟器恢复为原生状态（重新启用 + 重启）
      --preserve-boot-state
                       让最初处于关机状态的模拟器在完成后回到关机状态
  enable <udid> <ids>  在已启动的模拟器上立即重新启用类别或独立守护进程，
                       无需重启。ID 为类别 ID 或 launchd 标签，可用逗号或
                       空格分隔。与 'on --no-reboot' 一样，状态持续到下一次
                       'on' 或 'watch' 处理重新应用配置
      --save 路径      同时把它们加入该配置文件（类别写入 "except"，守护
                       进程写入 "keep"），必要时从默认配置创建；模拟器未
                       启动时仅修改文件
  disable <udid> <ids> 在已启动的模拟器上立即停止类别或守护进程，无需重启。
                       若某守护进程同时属于另一个完全启用的类别，则保持
                       运行。要回到某个配置，运行
                       'on <udid> --no-reboot --profile 路径'
      --save 路径      同时把它们从该配置文件中移除
  watch                持续为所有模拟器瘦身，直到 Ctrl-C：在运行时允许时
                       （iOS/tvOS 18.5+、watchOS 11.5+、visionOS 2.5+）
                       于关机模拟器启动前瘦身，使其首次启动就不加载配置内
                       的守护进程；并在启动过程中以不重启方式瘦身。该钩子
                       也适用于 xcodebuild 并行测试克隆 —— 它们按运行创建、
                       为原生状态且用完即删；请用 --set 指向并行测试设备集
      --profile 路径   应用已提交的 JSON 配置（见下文）；与
                       --except/--keep 互斥
      --except ids     保持这些类别启用（逗号分隔）
      --keep labels    保持这些独立守护进程运行（逗号分隔）
      --interval 时长  重新扫描正在启动的模拟器的间隔（默认 3s）
  status <udid>        报告已启动模拟器的瘦身程度
      --dropped        同时按类别列出已停用的守护进程
  verify <udid>        检查已启动模拟器的停用覆盖项是否仍与配置完全一致；
                       不一致则以非零状态退出并列出偏差。可发现被静默重建
                       或抹掉后恢复原生的设备；重新运行 'on' 修复
      --profile 路径   对照已提交的 JSON 配置校验；与 --except/--keep 互斥
      --except ids     配置中保持启用的类别（逗号分隔）
      --keep labels    配置中保持运行的守护进程（逗号分隔）
  doctor <udid>        对照已启动的模拟器检查必需功能；若瘦身破坏了任何
                       功能则以非零状态退出
      --requires ids   要校验的功能 ID（逗号分隔）
      --list           列出所有可检查的功能及其守护进程
  measure <udid>       报告已启动模拟器的内存占用
  top [udid]           实时机群监控：已启动模拟器及其内存、CPU 与进程数。
                       回车进入某台模拟器查看各守护进程占用。传入 UDID
                       可直接打开该详情。--json 输出一次性快照
  size <udid>          报告模拟器已分配的磁盘占用
  disk-categories      显示可清理及受保护的系统资源类别
  disk-plan <udid>     测量可回收空间与已存储数据，不执行删除
  disk-clean <udid>    永久删除所选的设备数据
      --categories ids 可清理类别 ID（逗号分隔）
      --confirm        永久删除所需的确认标记
      --preserve-boot-state
                       清理前处于启动状态的模拟器将被重启
  clone <udid> <名称>  克隆应用、数据、设置与服务配置
  repair-clone <源UDID> <克隆UDID>
                       修复现有克隆中绑定到源设备的状态
  rename <udid> <名称> 重命名模拟器
  boot <udid>          启动模拟器并等待其服务就绪
  shutdown <udid>      关闭已启动的模拟器
  erase <udid>         抹掉模拟器的应用、数据与设置
  delete <udid>        永久删除模拟器
      --json           输出机器可读 JSON（list、profiles、status、verify、
                       doctor、enable、disable 及模拟器管理命令同样支持）
  version              输出版本号

停用是持久化的（保存在模拟器的 launchd 覆盖项中），可用 'simslim off'
完全撤销。易导致死锁的守护进程永不被改动。
'simslim enable' 与 'simslim disable' 只实时修改已启动的模拟器，不保存
状态；配合 --save 才会同时修改配置文件 —— 这是瘦身模拟器的唯一记录，
'on'、'watch' 与 'verify' 都会读回它。

'--profile' 文件是可与项目一起提交的 JSON，按每次运行应用（例如 ci.json
与 dev.json）。其中的 "except" 与 "keep" 数组对应同名参数：

  { "name": "ci", "except": ["search", "store"], "keep": ["com.apple.apsd"] }

清理会永久删除已有的缓存、日志、诊断与临时文件内容；抹掉操作不会找回
这些历史，但随着 iOS 与应用运行，新生成的数据会再次出现。已下载的语言
数据为按需开启，功能需要时可能重新下载。必需的 Siri 资源仅作信息展示，
因为删除后 iOS 会自行恢复。simslim 从不修改共享的 iOS 运行时。

  https://github.com/mobai-app/simslim · by MobAI (https://mobai.run)
`
