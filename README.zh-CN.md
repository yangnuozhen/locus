# Locus

Locus 是一款免费、开源的 iPhone 模拟定位应用。你可以在地图上选点、搜索地点或规划路线。Locus 通过 Apple 的**开发者定位模拟服务**向 `locationd` 注入坐标，让地图和其他应用读取模拟位置，而不是只修改可能被 GPS 覆盖的 Wi‑Fi 定位结果。

[English](README.md)

<p align="center">
  <img src="docs/screenshots/zh-CN/settings.jpg" alt="Locus 地图与标记" width="180" />
  <img src="docs/screenshots/zh-CN/spoofing.jpg" alt="Locus 模拟定位" width="180" />
  <img src="docs/screenshots/zh-CN/joystick.jpg" alt="Locus 摇杆" width="180" />
  <img src="docs/screenshots/zh-CN/route.jpg" alt="Locus 路线" width="180" />
</p>

## 功能

- 一键定位到地图标记或搜索结果
- 实时摇杆移动：步行、跑步、骑行或驾车，并带有轻微速度变化
- 使用 MapKit 规划步行或驾车路线
- 绘制路线，或导入、导出 GPX 文件
- 后台保活、实时状态显示和定位中断提醒
- 收藏和最近位置；地图上的手动标记也可以命名并收藏
- 英文和简体中文界面
- 可选坐标转换，在发送定位前转换坐标
- 首次使用引导
- 所有数据均保留在设备上；不含分析功能，也不会上传数据

## 安装与首次使用

从 [GitHub Releases](https://github.com/ChrisMack32/Locus/releases) 下载 IPA，并使用 Feather、SideStore、AltStore、Sideloadly 或 LiveContainer 等侧载工具安装。也可以按下文从源码构建。

应用 Bundle ID：`com.chrismack.locus`

### 配对 iPhone

RPPairing 文件是 Locus 连接 iPhone 开发者定位服务所需的配对凭据，不是定位数据。通常只需导入一次，请妥善保管，不要公开分享。

- **iOS 27：**打开 Locus 的“设置 → 在此 iPhone 上配对 → 开始配对”，允许所需权限；然后前往 iPhone“设置 → 隐私与安全性 → 开发者模式 → 与主机配对”，选择 Locus 并按提示输入设备密码和 Locus 显示的六位验证码。配对完成后，文件会保存在设备上，无需电脑。
- **iOS 18–26：**在电脑上使用 [idevice_pair](https://github.com/jkcoxson/idevice_pair/releases) 生成 RPPairing 文件。连接并信任 iPhone 后，将文件通过 AirDrop 或分享菜单打开到 Locus，再导入；也可以在 Locus 中从剪贴板粘贴文件内容。请导入 **RPPairing** 文件，不要使用 lockdown 或 SideStore 的 `.mobiledevicepairing` 文件代替。

### 连接隧道并开始定位

可连接 [LocalDevVPN](https://apps.apple.com/us/app/localdevvpn/id6755608044)，或在 Shadowrocket 等兼容 VPN 中启用开发者隧道及 `10.7.0.1/32` 包含路由。默认隧道 IP 为 `10.7.0.1`，无需额外安装 LocalDevVPN。首次启动模拟定位时请连接 Wi‑Fi；启动后可以切换到蜂窝网络继续使用。

在地图上点选位置，然后点击“模拟定位”。也可以先搜索地点。模拟定位启动后可使用摇杆、路线和 GPX 功能。

### LiveContainer 文件选择器

如果 LiveContainer 中的文件选择器无法正常工作，可以在 LiveContainer 中长按 Locus，打开设置并启用 **Fix File Picker**；也可以通过 iOS 分享菜单将配对文件直接交给 LiveContainer 中的 Locus，或复制 plist 完整内容后在 Locus 的设置或首次设置页面粘贴。

## 语言

Locus 支持英文和简体中文，**应用内目前没有语言切换按钮**。界面语言跟随 iOS 的首选语言。要使用简体中文，请前往 iPhone“设置 → 通用 → 语言与地区”，添加“简体中文”并将其设为首选语言。若 iOS 为 Locus 提供单独的语言设置，也可以在系统设置中单独选择。

## 地图标记与收藏

点击地图可放置标记。选中标记后，点击“收藏此位置”并确认名称；也可以使用地图上方的星形按钮。名称留空时会以坐标作为名称。收藏会保存在“地点”中，重启应用后仍可使用。搜索地点仍会自动保存搜索结果。

## 中国大陆坐标转换

在 **设置 → 坐标转换** 中选择转换方式。默认是“关闭”，因此安装后需要按坐标来源和接收定位的应用主动选择；开始模拟定位后需先停止，才能更改该选项。

- **GCJ-02 → WGS-84：**当输入地图标记使用 GCJ-02，而定位服务需要 WGS-84 时使用。中国大陆地图标记与系统定位之间若相差数百米，可以先尝试此项；Locus 在一个实际大陆使用场景中已验证此设置可消除偏移。
- **WGS-84 → GCJ-02：**输入坐标为 WGS-84，而接收方需要 GCJ-02 时使用。
- **WGS-84 → BD-09：**输入坐标为 WGS-84，而接收方使用百度 BD-09 坐标时使用。
- **关闭：**不改变输入坐标。

请根据**坐标来源和接收方**选择方向，不能只根据界面语言或所在地区判断。选错方向可能让偏移变得更大。坐标转换只发生在发送定位时；地图标记、收藏、最近位置和 GPX 文件会保留原坐标。转换算法离线运行，使用经纬度范围粗略判断中国大陆区域，不是精确国界，也不会自动识别地图提供方的坐标系。边境区域及其他地区建议关闭转换。有关不同坐标类型的说明可参阅[百度地图坐标系文档](https://lbsyun.baidu.com/docs/webapi?title=mapadjustment%2Furi%2Fweb)。

转换会应用于 Teleport、路线、摇杆更新和定时重发。单元算法检查可在 macOS 上运行：

```sh
xcrun swiftc -module-cache-path /tmp/locus-swift-module-cache \
  Locus/Engine/CoordinateTransform.swift Tests/CoordinateTransformChecks.swift \
  -o /tmp/locus-coordinate-checks
/tmp/locus-coordinate-checks
```

## 工作原理

Locus 使用 MIT 许可的 [idevice](https://github.com/jkcoxson/idevice) FFI，通过设备上的开发者隧道与 Apple DVT 定位模拟服务通信。这与 Xcode 使用的定位模拟机制属于同一类方式。

## 从源码构建

从源码构建需要 Apple Developer 账号（免费或付费均可）用于代码签名。下载发布版 IPA 后，可以通过侧载工具完成安装。

1. 如尚未安装 XcodeGen，可运行 `brew install xcodegen`。
2. 在 `project.yml` 中设置开发者 **Team ID**（`DEVELOPMENT_TEAM`），或生成工程后在 Xcode 的“Signing & Capabilities”中选择团队。
3. 生成并打开 Xcode 工程：

```sh
xcodegen generate
open Locus.xcodeproj
```

也可以在命令行构建（将 `YOUR_TEAM_ID` 替换为 Apple Developer 账号 Membership 页面显示的 Team ID）：

```sh
xcodegen generate
xcodebuild -project Locus.xcodeproj -scheme Locus -configuration Release \
  -destination 'generic/platform=iOS' DEVELOPMENT_TEAM=YOUR_TEAM_ID build
```

构建成功不代表真机配对或定位隧道已验证。真机使用还需要导入配对凭据，并连接 LocalDevVPN 或其他兼容的开发者隧道。

## 许可证

Locus 使用 MIT 许可证。[Vendor/idevice](Vendor/idevice) 中包含 MIT 许可的 idevice FFI。Locus 是独立开源项目，与 Mirage / Wapixel 无隶属关系。

## 自定义速度与随机模拟

点击步行、跑步、单车、驾车旁的速度表按钮，输入 **0.1–300 km/h** 的自定义速度
（默认 5 km/h）。保存后切换到自定义，取消则保留当前模式。摇杆与路线共用速度，
行进中修改也会生效。自定义速度时，可在路线页单独选择「步行道路 / 驾车道路」，
默认步行。改变速度不会自动重新规划已有路线。

在 **设置 → 随机模拟** 中可调整：

- **位置随机漂移**：默认关闭，默认最大半径 3 米，可设 1–100 米。定点停留、摇杆和
  路线均生效，始终围绕理想位置，不会不断累积偏移。
- **行动速度随机变化**：默认开启 ±10%，可设 0–90%。例如基础速度 5 km/h、±10%
  对应 4.5–5.5 km/h；摇杆仍保留力度控制。

随机目标每 3 秒平滑变化，关闭后下次更新即清除效果。设置和自定义速度会自动保存。
收藏、历史及导出的 GPX 保留理想坐标；地图模拟位置标记显示坐标转换之前的发送位置。
位置写入失败会停止行进，重连后需手动重新启动摇杆或路线。

### 编译未签名 IPA

在安装完整 Xcode 26.3 和 XcodeGen 的 Mac 上运行：

```sh
scripts/build-unsigned-ipa.sh
```

脚本运行运动与坐标转换检查、重新生成工程，以 `CODE_SIGNING_ALLOWED=NO` 归档真机
Release 应用，并按 `Payload/Locus.app` 结构打包。输出位于 `outputs/`，包括
`Locus-unsigned.ipa`、SHA-256 校验和、源码版本/状态和构建日志，无需签名证书。
未签名 IPA 运行前仍需要自行签名或使用兼容容器。

也可以将源码推送至有写权限的 GitHub 仓库，在 **Actions → Build unsigned IPA
(artifact) → Run workflow** 手动构建，下载生成的 artifact。产物保留 14 天，
不会发布 Release。

配对 iPhone 后请验证定点漂移、摇杆不同力度、道路/绘制/GPX 路线、行进中调速、停止、
模式切换、隧道断连重连及后台恢复，同时检查中英文、小屏和大字体。独立计算检查不代表
已完成真机功能验证。

## Shadowrocket 等开发者隧道

`10.7.0.1/32` 是 VPN 包含路由，Remote Pairing 的 TCP 服务端口是另一项配置。
旧版 Locus 固定使用 49152，服务重启或重新建立配对/环境后，实际端口可能变化；仅有
正确的路由不保证固定端口可用。不能仅凭探测失败判定 Shadowrocket 配置错误。

新版在 **设置 → 隧道** 默认开启「自动发现 Remote Pairing 端口」：先用 BSD socket
尝试该 IP 上次确认可连接的端口（无缓存时为 49152），再通过 Bonjour 查找本机
`_remotepairing._tcp` 服务。发现结果仍通过原有 VPN IP 连接，不改 VPN 配置。
成功连接新端口后更新缓存；不会把附近其他手机的服务端口直接用于当前设备。

首次传送、启动摇杆或路线会先等待端口发现，实际定位引擎也使用同一端口。取消或替换
等待中的操作后，不会突然执行旧的定位请求。定位活动期间不建立额外探测连接。

若 Bonjour 无法发现：在 SideStore 的 **Connection Config** 查看当前生效的
**RemotePair Port**，在 Locus 关闭自动发现并填写相同端口，保存后再试；IP 保持
`10.7.0.1`。重新开启自动发现后恢复自动更新。请允许 Locus 或其所在容器访问本地网络。

状态「Remote Pairing 端口尚未验证」只表示当前端口未通过探测，不再等同于隧道不可达。
传送会进行实际配对和开发服务握手；若失败，提示包含实际端点、失败阶段与原生数值错误码，
不包含配对内容。SideStore 能连接不等于 Locus 导入的配对文件和定位服务已验证。

测试涵盖端口变化、按 IP 隔离缓存、手动优先级、服务地址筛选、BSD socket 成功/拒绝及取消。
Bonjour、iOS 本地网络权限及 Shadowrocket 完整链路仍需配对 iPhone 实测。

后续构建参见 [GitHub 凭据配置说明](docs/github-build-access.md)。

## 路线暂停、继续与停止

主地图底部和路线面板都会显示当前路线状态、进度和控制按钮：

- **暂停路线**：保留当前位置和行进进度，后续可继续；暂停时间不会计入下一次行进。
- **继续路线**：从暂停点继续，并采用当前速度设置。
- **停止路线**：结束本次路线播放，保留当前模拟位置；如需重播，在路线面板重新开始。
- **结束定位**：清除模拟位置并恢复真实 GPS。这与停止路线分开。

路线自然完成后同样保留终点。暂停、停止及完成后，若开启随机漂移，漂移仍围绕固定的
理想位置中心进行，不会继续沿路线前进。定位写入失败会停止行进，重连后不会自动继续。

## 多段道路路线

1. 打开 **路线 → 在地图上连续选点**，依次点选起点、途经点和终点；也可在此模式下搜索
   地点直接加入。地图和列表使用相同编号，点击「撤销上一站」可撤销最后一次选点。
2. 点击「完成」返回路线面板。也可用「将当前图钉添加为下一站」逐个追加，或先用当前
   模拟位置/定位作为起点。
3. 点击「编辑」拖动排序或删除站点。首个站点是起点、最后一个是终点，中间是途经点；
   在末尾添加新点后，之前的终点自动成为途经点。
4. 点击 **生成完整路线**。应用按同一道路类型逐段规划，显示生成进度并支持取消；某一段
   失败会显示段号及原因，不会把不完整结果作为完整路线。
5. 生成后查看总距离，点击 **开始路线**。各段会连续播放，GPX 导出也包含完整连接路线。

修改站点或道路类型后需重新生成。正在运行或暂停的路线不受规划草稿修改影响；请先停止
当前路线，再开始新路线。单独导入的 GPX 和绘制路径同样支持暂停、继续和停止。
道路规划需 Apple Maps 网络服务；生成取消或切换草稿后，过期请求不会覆盖当前结果。
站点草稿与播放进度暂不跨应用重启保存。

本轮真机验收建议：漂移开/关各检查暂停与停止后的中心位置；暂停几分钟再继续确认无跳点；
停止后等待超过 12 秒检查位置保持；切换摇杆、传送及结束定位；三站以上连续规划、排序、
删除、取消生成、规划失败及 GPX 导出；在后台暂停再回前台继续。
