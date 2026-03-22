#!/usr/bin/env bash
set -euo pipefail

IMAGE_PATH="${1:-}"

if [[ -z "${IMAGE_PATH}" ]]; then
  echo "Usage: $0 <path-to-image.img>" >&2
  exit 1
fi

if [[ ! -f "${IMAGE_PATH}" ]]; then
  echo "Image not found: ${IMAGE_PATH}" >&2
  exit 1
fi

require_cmd() {
  local cmd
  for cmd in "$@"; do
    command -v "${cmd}" >/dev/null 2>&1 || {
      echo "Required command is missing: ${cmd}" >&2
      exit 1
    }
  done
}

require_cmd losetup mount umount findmnt sed grep awk mkdir rm ln sync

LOOP_DEV=""
ROOT_MNT=""
BOOT_MNT=""

cleanup() {
  set +e
  if [[ -n "${BOOT_MNT}" ]] && findmnt -rn "${BOOT_MNT}" >/dev/null 2>&1; then
    umount "${BOOT_MNT}"
  fi
  if [[ -n "${ROOT_MNT}" ]] && findmnt -rn "${ROOT_MNT}" >/dev/null 2>&1; then
    umount "${ROOT_MNT}"
  fi
  if [[ -n "${BOOT_MNT}" ]]; then
    rmdir "${BOOT_MNT}" 2>/dev/null || true
  fi
  if [[ -n "${ROOT_MNT}" ]]; then
    rmdir "${ROOT_MNT}" 2>/dev/null || true
  fi
  if [[ -n "${LOOP_DEV}" ]]; then
    losetup -d "${LOOP_DEV}" 2>/dev/null || true
  fi
}

trap cleanup EXIT

backup_file() {
  local path="$1"
  if [[ -e "${path}" ]]; then
    cp -a "${path}" "${path}.bak-safe-lan"
  fi
}

disable_unit_offline() {
  local root="$1"
  local unit="$2"
  rm -f "${root}/etc/systemd/system/multi-user.target.wants/${unit}"
  rm -f "${root}/etc/systemd/system/basic.target.wants/${unit}"
  rm -f "${root}/etc/systemd/system/network-online.target.wants/${unit}"
  mkdir -p "${root}/etc/systemd/system"
  ln -snf /dev/null "${root}/etc/systemd/system/${unit}"
}

prepare_rootfs_safe_lan() {
  local root="$1"
  local env_file="${root}/boot/orangepiEnv.txt"
  local modules_file="${root}/etc/modules"

  [[ -f "${env_file}" ]] || {
    echo "Missing boot config: ${env_file}" >&2
    exit 1
  }
  [[ -f "${modules_file}" ]] || {
    echo "Missing modules file: ${modules_file}" >&2
    exit 1
  }

  backup_file "${env_file}"
  backup_file "${modules_file}"

  sed -i -E 's/^verbosity=.*/verbosity=1/' "${env_file}"
  sed -i -E '/^extraargs=/d' "${env_file}"
  printf '%s\n' 'extraargs=modprobe.blacklist=aic8800_fdrv,aic8800_btlpm,aic8800_bsp' >> "${env_file}"

  sed -i \
    -e 's/^aic8800_fdrv$/# aic8800_fdrv/' \
    -e 's/^aic8800_btlpm$/# aic8800_btlpm/' \
    "${modules_file}"

  mkdir -p "${root}/etc/modprobe.d"
  cat > "${root}/etc/modprobe.d/blacklist-aic8800-safe-lan.conf" <<'EOF'
# Disable onboard Wi-Fi/BT stack for stable LAN-only boot.
blacklist aic8800_fdrv
blacklist aic8800_btlpm
blacklist aic8800_bsp
EOF

  disable_unit_offline "${root}" hostapd.service
  disable_unit_offline "${root}" dnsmasq.service
  disable_unit_offline "${root}" openvpn.service
  disable_unit_offline "${root}" bluetooth.service

  rm -f "${root}/etc/systemd/system/multi-user.target.wants/networking.service"

  if [[ -f "${root}/etc/default/orangepi-zram-config" ]]; then
    backup_file "${root}/etc/default/orangepi-zram-config"
    sed -i -E 's/^ENABLED=.*/ENABLED=true/' "${root}/etc/default/orangepi-zram-config"
  fi

  if [[ -f "${root}/etc/default/orangepi-ramlog" ]]; then
    backup_file "${root}/etc/default/orangepi-ramlog"
    sed -i -E 's/^ENABLED=.*/ENABLED=true/' "${root}/etc/default/orangepi-ramlog"
  fi
}

wait_for_partitions() {
  local loop_dev="$1"
  local i

  for i in $(seq 1 10); do
    if [[ -b "${loop_dev}p2" || -b "${loop_dev}p1" ]]; then
      return 0
    fi
    sleep 1
  done

  return 1
}

LOOP_DEV="$(losetup --find --show --partscan "${IMAGE_PATH}")"
wait_for_partitions "${LOOP_DEV}" || {
  echo "Partition nodes did not appear for ${LOOP_DEV}" >&2
  exit 1
}

BOOT_PART="${LOOP_DEV}p1"
ROOT_PART="${LOOP_DEV}p2"

if [[ ! -b "${ROOT_PART}" ]]; then
  echo "Root partition not found: ${ROOT_PART}" >&2
  exit 1
fi

ROOT_MNT="$(mktemp -d)"
mount "${ROOT_PART}" "${ROOT_MNT}"

if [[ -b "${BOOT_PART}" ]]; then
  BOOT_MNT="${ROOT_MNT}/boot"
  mkdir -p "${BOOT_MNT}"
  mount "${BOOT_PART}" "${BOOT_MNT}"
fi

prepare_rootfs_safe_lan "${ROOT_MNT}"
sync

echo "Prepared image for stable LAN-only boot: ${IMAGE_PATH}"
