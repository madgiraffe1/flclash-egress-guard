# FlClash 出网保护

Mac 菜单栏里的盾牌。开启日常保护后，普通应用通过 FlClash 访问公网。FlClash 退出或虚拟网卡掉线时，防火墙会锁住公网，局域网和本机服务仍可使用。

## 安装

1. 在 Apple 芯片 Mac 上[下载 App 压缩包](https://github.com/madgiraffe1/flclash-egress-guard/releases/latest/download/FlClash-Egress-Guard-macOS-arm64.zip)，双击解压。
2. 把「FlClash 出网保护.app」放到个人应用程序目录 `~/Applications/`。FlClash 本体应装在 `/Applications/FlClash.app`。
3. 双击盾牌 App，点「一次授权」，在 macOS 窗口输入管理员密码。点「开启日常保护」后，面板会逐步提示需要的操作。

点菜单栏盾牌可以查看和刷新状态。掉线后点「重新接通 FlClash」恢复受保护的连接。点「开启开机保护」后，下次登录桌面会自动显示盾牌。

发布包采用本机签名，未经 Apple 公证。构建目标为 macOS 13 及以上，运行需要可用的 `/usr/bin/python3`。

## 源码和恢复

在已安装 Xcode 命令行工具的 Mac 上，从仓库根目录运行以下命令即可构建当前芯片架构的 App。

```sh
sh app/build.sh "FlClash 出网保护.app"
```

需要恢复原来的上网方式时，在 App 中点「解除全部保护…」。离线回滚命令、撤销授权和开机保护的说明见[使用手册](outputs/flclash-guard/README.md)。
