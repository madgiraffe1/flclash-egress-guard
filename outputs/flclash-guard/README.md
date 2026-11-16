# FlClash 出网保护

## Mac App

在访达打开个人「应用程序」里的「FlClash 出网保护」。首次点「一次授权」，在 macOS 自己的窗口输入管理员密码。以后点菜单栏盾牌就能查看日常保护、开机保护和最近核对时间，点「刷新状态」可立即重读。

点「开启日常保护」后，面板按实际进度显示四步：核对状态、接通 FlClash、启用规则、验证联网。已经生效的规则会直接进入联网验证。出现「需要你操作」时照提示处理，再点「继续」。某一步未完成时，面板保留这一步的原因和「重试」按钮。

一次授权安装的系统助手按需运行，只接受当前用户获准版本的盾牌 App 调用防火墙的固定操作。授权跨重启有效，更新 App 后可能需要重新授权。点「撤销授权…」可移除助手，当前防火墙继续工作。

日常保护显示「公网已锁住」时，点「打开面板」，再点「重新接通 FlClash」。App 会在保护下打开 FlClash。如果普通方式启动的 FlClash 正在运行，请等 App 提示后手动退出一次。关主窗口后菜单栏盾牌继续显示，退出 App 会收起盾牌。

「开启开机保护」登记一次即可。系统启动服务负责锁公网，个人登录项 `~/Library/LaunchAgents/local.flclash-egress-guard.panel.plist` 在登录桌面时自动打开本 App 的菜单栏盾牌。登录项只启动一次，不弹出主窗口。取消开机保护也会取消菜单栏登录启动。「解除全部保护」会恢复原来的出网方式，同时取消两项启动登记。关闭面板不会解除保护。下面的访达脚本可用作备用入口。

## 日常和开机使用

1. 在访达双击「开机保护.command」，输入 `1` 并按回车。它为下次开机登记保护，今天想立即开启可直接双击「开启日常保护.command」。
2. 下次正常开机、登录后，双击「开启日常保护.command」。它会先核对已载入的开机锁定状态，再测 Google、抖音和绑定 Wi-Fi 的固定目标。然后按提示用受保护的方式打开 FlClash。若普通方式启动的 FlClash 已经打开，窗口会提示你手动退出一次。
3. 看到「日常保护已开启」，就可以关掉窗口。退出 FlClash 后公网会锁住。要受保护地继续上网，再双击「开启日常保护.command」。
4. 想取消以后开机自动保护，在「开机保护.command」选 `2`，本次保护继续。要立刻恢复原来的上网方式并取消开机保护，双击「恢复上网.command」。开机菜单选 `3` 可以查看实际状态。显示「开机保护已设置」表示已登记。下次开机看到「本次开机启动项已确认过公网锁定」以及接通前的检测通过，才有本次启动和登录后阻断的记录。

日常保护和恢复上网的记录都在 `~/Library/Logs/FlClashEgressGuard/保护日志.txt`，也可以在 App 中点「查看日志」。每行只记时间、检查名称和通过或不通过。

## 停用和完整回滚

在访达双击「恢复上网.command」即可离线恢复。要在本目录的终端手动操作，可用下面的命令。

```sh
sudo ./egress-guard disable
sudo ./egress-guard rollback
```

`disable` 会取消开机项、移除本工具在 `/etc/pf.conf` 追加的段落、清空自己的活动规则、释放自己的 pf 引用，保留专用组。`rollback` 还会删除本工具创建的组和系统记录。如果 FlClash 仍占用专用组，出网会先恢复。等你手动退出 FlClash 后再运行一次 `rollback` 即可清完。`boot-on` 只登记下次开机，`boot-off` 只取消以后开机自动保护。`status` 可同时查看开机设置和当前防火墙。

若找不到访达里的备用脚本，也可在终端调用 App 自带的控制器。下面的命令会恢复上网并清理两项启动登记。

```sh
sudo "$HOME/Applications/FlClash 出网保护.app/Contents/Resources/egress-guard" rollback
```

如需卸载，完成回滚后在 App 里点「撤销授权…」，再退出盾牌并将 App 移到废纸篓。也可以在终端单独撤销一次授权：

```sh
sudo "$HOME/Applications/FlClash 出网保护.app/Contents/Resources/guard-authorize" remove "$(id -u)"
```

## 系统设置

目标是在这台 Mac 上保留 FlClash 的代理和 DIRECT 分流。公网 TCP、UDP 出口要求套接字同时具有有效 UID 0 和本工具的专用有效 GID。普通 root 服务、Claude 和它启动的子进程都没有这个组合。pf 判断的是套接字凭据，程序文件名只用于启动前核对。IPv4 和 IPv6 使用同一个最终阻断规则。

| 项目 | 内容 |
| --- | --- |
| 系统文件 | 在 `/private/var/db/flclash-egress-guard/` 保存组的归属记录、pf 引用和本次启用状态。 |
| 专用组 | `start` 创建无成员的本地组 `_flclashguard`。GUI 在当前用户桌面、以用户 UID 和新有效 GID 运行。核心沿用应用自带的提权方式。 |
| pf | 使用系统现成的 `com.apple/*` 挂点，只在 `com.apple/000.flclash-egress-guard` 加载规则。通过 `-E/-X` 持有和释放自己的启用引用。 |
| 可选开机项 | 选「开启开机保护」后，向 `/etc/pf.conf` 追加本工具的开机规则加载行，另存 `/etc/pf.anchors/local.flclash-egress-guard`、`/Library/LaunchDaemons/local.flclash-egress-guard.plist`，以及管理员所有的 `/Library/Application Support/FlClashEgressGuard/`。 |
| 局域网 | 保留回环、RFC 1918、IPv4 链路本地、IPv6 ULA 和链路本地、本地链路组播、DHCP 广播。发往局域网路由器的 DNS 也属于这个例外。 |
| 公网进程白名单 | 仅 FlClashCore。mDNSResponder 的本地组播已覆盖，系统更新、校时和 iCloud 没有独立的公网例外。 |
| 断线 | 普通进程发往物理接口的公网包在联网期间也会被拦。核心退出触发内核进程通知。若只有 TUN 消失或其路由变化，运行期监视器约每秒核对一次，确认后撤下核心和 TUN 两条例外，锁住公网。检测间隔内，仍在运行的核心可能继续服务显式本机代理。要恢复受保护的上网方式，再双击「开启日常保护.command」。 |

FlClash 继续使用原有的分流规则、订阅、覆写、代理组和 DNS。停用、回滚和查看状态均可离线操作。

这台 Mac 的系统服务在启动时读取 `/etc/pf.conf`。可选服务等默认阻断规则已经载入后打开 pf，再核对挂点、接口和连接状态。这个服务只负责封锁。日常按钮读回公网阻断后才按你的操作启动 FlClash，核对专用组、核心和 TUN 后才放行。系统规则被重读时，开机规则也会回到锁定状态，可用日常按钮重新接通。

macOS 并行启动系统服务。这里能控制由日常按钮启动的 FlClash 的先后顺序。对于 PF 生效前的启动早期，以及通过其他登录项独立启动的程序，系统没有给这个脚本提供发包顺序保证。接通前的检查记录的是登录时实际观测到的状态。[Apple 启动机制说明](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html)

## 查看状态

在这个目录打开本机终端。下面两个命令只读取现有会话并解析规则。第三个命令需要管理员身份才能读取活动规则和连接状态。

```sh
./egress-guard status
./egress-guard preview
sudo ./egress-guard check
```

若已有 pf 规则可能与本工具冲突、物理接口跳过 pf，或已有非局域网的连接状态可能绕过新规则，`check` 会给出原因。它不会清空全机状态表，也不会重载系统规则。
