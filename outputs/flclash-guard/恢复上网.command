#!/bin/sh
cd "$(dirname "$0")" || exit 1
umask 077
log_dir="$HOME/Library/Logs/FlClashEgressGuard"

log_result() {
    /bin/mkdir -p "$log_dir" && printf '%s\t%s\t%s\n' "$(/bin/date '+%Y-%m-%dT%H:%M:%S%z')" "$1" "$2" >> "$log_dir/保护日志.txt"
}

# Stop any waiting daily prompt before releasing the firewall.
./guard-guide cancel >/dev/null 2>&1
printf '%s\n' '现在解除本工具的断网限制，同时取消开机保护。如果提示 Password，输入 Mac 登录密码再按回车。'
if ! /usr/bin/sudo ./egress-guard disable; then
    log_result '手动恢复 · 解除出网限制' '不通过'
    printf '%s\n' '本次限制尚未确认解除。请重新打开「恢复上网.command」并确认输入的是这台 Mac 的登录密码。'
    exit 1
fi
log_result '手动恢复 · 解除出网限制' '通过'
printf '%s\n' '已恢复原来的上网方式。下次开机也不会由本工具锁住公网。'

if /usr/bin/sudo -n ./egress-guard rollback >/dev/null 2>&1; then
    log_result '手动恢复 · 清理临时设置' '通过'
else
    log_result '手动恢复 · 清理临时设置' '不通过'
    printf '%s\n' '临时设置尚未清完，出网限制已经解除。以后手动退出 FlClash 时，再双击一次这个文件即可重试清理。'
fi
if ! ./egress-guard preview >/dev/null 2>&1; then
    printf '%s\n' '如果 FlClash 已经退出，请你自己用平常的图标打开。'
    printf '%s\n' '等它打开后按回车，记录 Google 和抖音的恢复结果。现在关窗口也不会重新断网。'
    IFS= read -r reply || exit 0
fi
printf '%s\n' '正在复测 Google 和抖音。'
./guard-guide restored
printf '%s\n' '可在「FlClash 出网保护」App 里点「查看日志」。'
