#!/bin/bash
set -euo pipefail

finish() {
    result=$?
    if [[ -t 0 ]]; then
        printf '\n按回车关闭窗口。'
        read -r _ || true
    fi
    exit "$result"
}
trap finish EXIT

if [[ "$(/usr/bin/uname -s)" != 'Darwin' || "$EUID" -eq 0 ]]; then
    printf '请以当前登录用户在 macOS 上运行，不要使用 sudo。\n' >&2
    exit 1
fi

bundle_id='com.appshub.bettbox'
app="${1:-}"
if [[ -z "$app" ]]; then
    for candidate in "$HOME/Applications/maomaoyun.app" '/Applications/maomaoyun.app'; do
        if [[ -d "$candidate" ]]; then
            app="$candidate"
            break
        fi
    done
fi
if [[ -z "$app" ]]; then
    app=$(/usr/bin/osascript <<'APPLESCRIPT'
POSIX path of (choose application with prompt "请选择要卸载的猫猫云客户端" as alias)
APPLESCRIPT
    )
fi
app="${app%/}"
if [[ ! -d "$app" || -L "$app" || "$app" != /* || "$app" != *.app ]]; then
    printf '请选择实际安装的 .app 文件夹。\n' >&2
    exit 1
fi
app="$(cd "$(/usr/bin/dirname "$app")" && pwd -P)/$(/usr/bin/basename "$app")"
if [[ "$app" == /Volumes/* ]]; then
    printf '请选择已复制到磁盘的应用，不要选择 DMG 中的应用。\n' >&2
    exit 1
fi
actual_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")
binary="$app/Contents/MacOS/Bettbox"
if [[ "$actual_id" != "$bundle_id" || ! -x "$binary" ]]; then
    printf '所选应用不是受支持的客户端，已取消。\n' >&2
    exit 1
fi
/usr/bin/codesign --verify --deep --strict "$app"

printf '即将卸载：%s\n' "$app"
printf '1. 仅移除应用，保留登录信息、订阅和设置\n'
printf '2. 移除应用，同时清理当前用户的登录信息、订阅和设置\n'
printf '其他输入取消。清理数据后无法恢复。\n'
read -r -p '请选择 [1/2]：' choice
if [[ "$choice" != 1 && "$choice" != 2 ]]; then
    printf '已取消。\n'
    exit 0
fi
read -r -p '确认继续？请输入 YES：' confirm
if [[ "$confirm" != 'YES' ]]; then
    printf '已取消。\n'
    exit 0
fi

data_paths=(
    "$HOME/Library/Application Support/$bundle_id"
    "$HOME/Library/Caches/$bundle_id"
    "$HOME/Library/WebKit/$bundle_id"
    "$HOME/Library/HTTPStorages/$bundle_id"
    "$HOME/Library/Saved Application State/$bundle_id.savedState"
    "$HOME/Library/Preferences/$bundle_id.plist"
)
home_physical="$(cd "$HOME" && pwd -P)"
assert_data_path() {
    target="$1"
    if [[ ! -e "$target" && ! -L "$target" ]]; then return; fi
    if [[ -L "$target" ]]; then
        printf '数据路径是符号链接，已停止：%s\n' "$target" >&2
        exit 1
    fi
    parent=$(/usr/bin/dirname "$target")
    relative_parent="${parent#"$HOME/"}"
    if [[ "$(cd "$parent" && pwd -P)" != "$home_physical/$relative_parent" ]]; then
        printf '数据目录被重定向，已停止：%s\n' "$target" >&2
        exit 1
    fi
}
if [[ "$choice" == 2 ]]; then
    for target in "${data_paths[@]}"; do assert_data_path "$target"; done
fi

# Use the installed app to stop its proxy/core through the normal exit path.
# Do not kill processes belonging to another installation.
"$binary" --exit >/dev/null 2>&1 &
exit_pid=$!
for ((attempt=0; attempt<20; attempt++)); do
    if ! kill -0 "$exit_pid" 2>/dev/null; then break; fi
    /bin/sleep 1
done
if kill -0 "$exit_pid" 2>/dev/null; then
    kill -TERM "$exit_pid" 2>/dev/null || true
    printf '退出请求超时，请手动退出客户端后重试。\n' >&2
    exit 1
fi
wait "$exit_pid" || true
for ((attempt=0; attempt<20; attempt++)); do
    if ! /usr/bin/pgrep -x 'Bettbox' >/dev/null && ! /usr/bin/pgrep -x 'BettboxCore' >/dev/null; then break; fi
    /bin/sleep 1
done
if /usr/bin/pgrep -x 'Bettbox' >/dev/null || /usr/bin/pgrep -x 'BettboxCore' >/dev/null; then
    printf '仍有客户端或内核运行。请退出其他同源客户端后重试。\n' >&2
    exit 1
fi

# The app has the right keychain identity. It disables its login item and, only
# for option 2, deletes this build's login entry through Flutter Secure Storage.
arguments=(--prepare-uninstall)
if [[ "$choice" == 2 ]]; then arguments+=(--clear-user-data); fi
"$binary" "${arguments[@]}" >/dev/null 2>&1 &
prepare_pid=$!
for ((attempt=0; attempt<30; attempt++)); do
    if ! kill -0 "$prepare_pid" 2>/dev/null; then break; fi
    /bin/sleep 1
done
if kill -0 "$prepare_pid" 2>/dev/null; then
    kill -TERM "$prepare_pid" 2>/dev/null || true
    printf '卸载准备超时，应用尚未移除。请确认已运行新版客户端。\n' >&2
    exit 1
fi
if ! wait "$prepare_pid"; then
    printf '无法完成登录项或钥匙串处理，应用尚未移除，请退出登录后重试。\n' >&2
    exit 1
fi
if /usr/bin/pgrep -x 'Bettbox' >/dev/null || /usr/bin/pgrep -x 'BettboxCore' >/dev/null; then
    printf '客户端再次启动，已停止清理。\n' >&2
    exit 1
fi
if [[ "$choice" == 2 ]]; then
    for target in "${data_paths[@]}"; do
        assert_data_path "$target"
        if [[ -e "$target" ]]; then /bin/rm -rf -- "$target"; fi
    done
    /usr/bin/defaults delete "$bundle_id" >/dev/null 2>&1 || true
fi
/usr/bin/osascript - "$app" <<'APPLESCRIPT'
on run arguments
    tell application "Finder" to delete (POSIX file (item 1 of arguments) as alias)
end run
APPLESCRIPT
printf '应用已移到废纸篓。'
if [[ "$choice" == 2 ]]; then printf '当前用户的数据已清理。'; else printf '当前用户的数据已保留。'; fi
printf '\n'
