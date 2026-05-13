#!/usr/bin/env bash
#
# umount-plugins.sh - Tháo bind mount plugins của OTSD-Dashboard
#
# Vị trí: OTSD-Dashboard/scripts/umount-plugins.sh
# Usage:  sudo ./scripts/umount-plugins.sh
#
# Chạy trước khi:
#   - yarn osd clean (tránh xóa nhầm source repo qua mount)
#   - Các thao tác git lớn trên OTSD-Dashboard
#   - Reboot/shutdown (cho sạch)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DASHBOARD_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DASHBOARD_PLUGINS="${DASHBOARD_ROOT}/plugins"

TARGETS=(
  "${DASHBOARD_PLUGINS}/wazuh-main"
  "${DASHBOARD_PLUGINS}/wazuh-core"
  "${DASHBOARD_PLUGINS}/wazuh-check-updates"
  "${DASHBOARD_PLUGINS}/security"
)

if [[ $EUID -ne 0 ]]; then
  echo "ERROR: Script này cần quyền root. Chạy: sudo $0" >&2
  exit 1
fi

echo "==> Dashboard root: ${DASHBOARD_ROOT}"
echo "==> Unmounting plugins..."
echo

for target in "${TARGETS[@]}"; do
  target_short="${target#${DASHBOARD_ROOT}/}"

  if [[ ! -d "$target" ]]; then
    echo "  [SKIP] Không tồn tại: $target_short"
    continue
  fi

  if ! mountpoint -q "$target" 2>/dev/null; then
    echo "  [SKIP] Không phải mount point: $target_short"
    continue
  fi

  if umount "$target"; then
    echo "  [OK]   Unmounted: $target_short"
    # Xóa thư mục rỗng sau khi unmount
    rmdir "$target" 2>/dev/null || true
  else
    echo "  [FAIL] $target_short (có thể đang được dùng bởi yarn/node?)" >&2
  fi
done

echo
echo "==> Xong."
