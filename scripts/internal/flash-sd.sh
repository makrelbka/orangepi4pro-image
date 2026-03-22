#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
IMAGES_DIR="${ROOT_DIR}/images"

red() { printf '\033[0;31m%s\033[0m\n' "$*"; }
green() { printf '\033[0;32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[1;33m%s\033[0m\n' "$*"; }

die() {
  red "$*"
  exit 1
}

mkdir -p "${IMAGES_DIR}"

mapfile -t images < <(find "${IMAGES_DIR}" -maxdepth 1 -type f -name '*.img' | sort)
[[ ${#images[@]} -gt 0 ]] || die "No .img files found in ${IMAGES_DIR}"

echo
yellow "Available images:"
for i in "${!images[@]}"; do
  size=$(du -h "${images[$i]}" | awk '{print $1}')
  printf '  %d) %-60s %s\n' "$((i+1))" "$(basename "${images[$i]}")" "$size"
done

echo
read -r -p "Select image [1-${#images[@]}]: " image_idx
[[ "$image_idx" =~ ^[0-9]+$ ]] || die "Image selection must be numeric"
(( image_idx >= 1 && image_idx <= ${#images[@]} )) || die "Image selection out of range"
IMAGE_FILE="${images[$((image_idx-1))]}"

if [[ "$(uname -s)" == "Darwin" ]]; then
  mapfile -t disks < <(diskutil list | awk '/^\/dev\/disk[0-9]+/ {print $1}')
  [[ ${#disks[@]} -gt 0 ]] || die "No disks found"

  echo
  yellow "Available disks:"
  for i in "${!disks[@]}"; do
    info=$(diskutil info "${disks[$i]}" 2>/dev/null | awk -F': ' '/Device \/ Media Name|Disk Size/ {print $2}' | paste -sd ' | ' -)
    printf '  %d) %-12s %s\n' "$((i+1))" "${disks[$i]}" "$info"
  done

  echo
  read -r -p "Select target disk [1-${#disks[@]}]: " disk_idx
  [[ "$disk_idx" =~ ^[0-9]+$ ]] || die "Disk selection must be numeric"
  (( disk_idx >= 1 && disk_idx <= ${#disks[@]} )) || die "Disk selection out of range"
  TARGET_DISK="${disks[$((disk_idx-1))]}"
  TARGET_RAW="${TARGET_DISK/disk/rdisk}"

  echo
  red "About to erase and write ${IMAGE_FILE} to ${TARGET_DISK}"
  read -r -p "Type 'yes' to continue: " confirm
  [[ "$confirm" == "yes" ]] || exit 0

  diskutil unmountDisk "${TARGET_DISK}" >/dev/null
  if command -v pv >/dev/null 2>&1; then
    size_bytes=$(stat -f%z "${IMAGE_FILE}")
    sudo sh -c "pv -s ${size_bytes} '${IMAGE_FILE}' | dd of='${TARGET_RAW}' bs=1m"
  else
    sudo dd if="${IMAGE_FILE}" of="${TARGET_RAW}" bs=1m status=progress
  fi
  sync
  diskutil eject "${TARGET_DISK}" >/dev/null || true
else
  mapfile -t disks < <(lsblk -dno NAME,SIZE,MODEL | sed 's#^#/dev/#')
  [[ ${#disks[@]} -gt 0 ]] || die "No block devices found"

  echo
  yellow "Available disks:"
  for i in "${!disks[@]}"; do
    printf '  %d) %s\n' "$((i+1))" "${disks[$i]}"
  done

  echo
  read -r -p "Select target disk [1-${#disks[@]}]: " disk_idx
  [[ "$disk_idx" =~ ^[0-9]+$ ]] || die "Disk selection must be numeric"
  (( disk_idx >= 1 && disk_idx <= ${#disks[@]} )) || die "Disk selection out of range"
  TARGET_DISK=$(awk '{print $1}' <<<"${disks[$((disk_idx-1))]}")

  echo
  red "About to erase and write ${IMAGE_FILE} to ${TARGET_DISK}"
  read -r -p "Type 'yes' to continue: " confirm
  [[ "$confirm" == "yes" ]] || exit 0

  sudo umount "${TARGET_DISK}"* 2>/dev/null || true
  if command -v pv >/dev/null 2>&1; then
    size_bytes=$(stat -c%s "${IMAGE_FILE}")
    sudo sh -c "pv -s ${size_bytes} '${IMAGE_FILE}' | dd of='${TARGET_DISK}' bs=4M conv=fsync status=none"
  else
    sudo dd if="${IMAGE_FILE}" of="${TARGET_DISK}" bs=4M conv=fsync status=progress
  fi
  sync
fi

green "Done"
