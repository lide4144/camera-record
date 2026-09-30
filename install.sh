#!/usr/bin/env bash
# 安装 camera-record：~/.local/bin 软链 + 桌面菜单项。删除软链即卸载。
set -euo pipefail
src="$(cd "$(dirname "$0")" && pwd)"

mkdir -p "$HOME/.local/bin" "$HOME/.local/share/applications"
ln -sf "$src/camera-record" "$HOME/.local/bin/camera-record"

sed "s|@EXEC@|$src/camera-record|" "$src/camera-record.desktop" \
  > "$HOME/.local/share/applications/camera-record.desktop"
update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true

echo "已安装:"
echo "  命令   : ~/.local/bin/camera-record -> $src/camera-record"
echo "  菜单项 : ~/.local/share/applications/camera-record.desktop"
echo "自检     : camera-record --selftest"
