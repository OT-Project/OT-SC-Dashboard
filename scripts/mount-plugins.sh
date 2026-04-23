#!/usr/bin/env bash
#
# mount-plugins.sh - Bind mount Wazuh plugins vào plugins/ của Dashboard
#
# Vị trí: OT-SC-Dashboard/scripts/mount-plugins.sh
# Usage:  sudo ./scripts/mount-plugins.sh
#
# Giả định layout:
#   OT-Project/
#     ├── OT-SC-Dashboard/              <- repo hiện tại
#     │   ├── plugins/                   <- target mount point
#     │   └── scripts/mount-plugins.sh   <- script này
#     ├── OT-SC-Dashboard-Plugins/
#     └── OT-SC-Security-Plugin/
#

set -euo pipefail

# Resolve đường dẫn:
#   SCRIPT_DIR     = OT-SC-Dashboard/scripts/
#   DASHBOARD_ROOT = OT-SC-Dashboard/
#   PROJECT_ROOT   = OT-Project/ (cha của OT-SC-Dashboard)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DASHBOARD_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_ROOT="$(cd "$DASHBOARD_ROOT/.." && pwd)"

DASHBOARD_PLUGINS="${DASHBOARD_ROOT}/plugins"
SOURCE_PLUGINS="${PROJECT_ROOT}/OT-SC-Dashboard-Plugins/plugins"
SECURITY_PLUGIN="${PROJECT_ROOT}/OT-SC-Security-Plugin"

# Danh sách mount: "source|target"
MOUNTS=(
  "${SOURCE_PLUGINS}/main|${DASHBOARD_PLUGINS}/wazuh-main"
  "${SOURCE_PLUGINS}/wazuh-core|${DASHBOARD_PLUGINS}/wazuh-core"
  "${SOURCE_PLUGINS}/wazuh-check-updates|${DASHBOARD_PLUGINS}/wazuh-check-updates"
  "${SECURITY_PLUGIN}|${DASHBOARD_PLUGINS}/security"
)

# Check quyền root (cần cho mount --bind)
if [[ $EUID -ne 0 ]]; then
  echo "ERROR: Script này cần quyền root. Chạy: sudo $0" >&2
  exit 1
fi

# Check các repo anh em tồn tại
for dir in "OT-SC-Dashboard-Plugins" "OT-SC-Security-Plugin"; do
  if [[ ! -d "${PROJECT_ROOT}/${dir}" ]]; then
    echo "ERROR: Không tìm thấy '${dir}' trong ${PROJECT_ROOT}" >&2
    echo "Các repo OT-SC-* phải nằm cùng cấp với OT-SC-Dashboard" >&2
    exit 1
  fi
done

echo "==> Project root: ${PROJECT_ROOT}"
echo "==> Bind mounting plugins..."
echo

for entry in "${MOUNTS[@]}"; do
  source="${entry%%|*}"
  target="${entry##*|}"

  # Rút gọn đường dẫn hiển thị cho dễ đọc
  source_short="${source#${PROJECT_ROOT}/}"
  target_short="${target#${PROJECT_ROOT}/}"

  # Check source tồn tại
  if [[ ! -d "$source" ]]; then
    echo "  [SKIP] Source không tồn tại: $source_short"
    continue
  fi

  # Đã mount rồi thì bỏ qua
  if mountpoint -q "$target" 2>/dev/null; then
    echo "  [SKIP] Đã mount sẵn: $target_short"
    continue
  fi

  # Tạo target nếu chưa có (phải là thư mục rỗng)
  if [[ ! -d "$target" ]]; then
    mkdir -p "$target"
  elif [[ -n "$(ls -A "$target" 2>/dev/null)" ]]; then
    echo "  [WARN] Target không rỗng, bỏ qua: $target_short"
    echo "         Nếu đây là copy cũ, hãy xóa trước: rm -rf $target"
    continue
  fi

  # Bind mount
  if mount --bind "$source" "$target"; then
    echo "  [OK]   $source_short -> $target_short"
  else
    echo "  [FAIL] $source_short -> $target_short" >&2
  fi
done

echo
echo "==> Xong. Kiểm tra: mount | grep $(basename $DASHBOARD_ROOT)/plugins"
