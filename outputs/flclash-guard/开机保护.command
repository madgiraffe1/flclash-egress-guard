#!/bin/sh
cd "$(dirname "$0")" || exit 1

printf '%s\n' '1  开启开机保护（下次开机自动锁住公网）' \
    '2  取消开机保护（保留本次已开启的日常保护）' \
    '3  查看开机设置和当前保护状态' '直接按回车退出。'
printf '%s' '请选择 1、2 或 3，再按回车：'
IFS= read -r choice || exit 0
case "$choice" in
    1) action=boot-on ;;
    2) action=boot-off ;;
    3) action=status ;;
    '') exit 0 ;;
    *) printf '%s\n' '未选择任何操作。'; exit 1 ;;
esac
printf '%s\n' '如果出现 Password，输入 Mac 登录密码再按回车。输入时屏幕不会显示字符。'
exec /usr/bin/sudo ./egress-guard "$action"
