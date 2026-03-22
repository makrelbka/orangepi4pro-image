#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGES_DIR="${SCRIPT_DIR}/images"
INTERNAL_BUILD="${SCRIPT_DIR}/scripts/internal/build-image.sh"

green() { printf '\033[0;32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[1;33m%s\033[0m\n' "$*"; }
red() { printf '\033[0;31m%s\033[0m\n' "$*"; }

die() {
  red "$*"
  exit 1
}

choose_option() {
  local prompt="$1"
  local default="$2"
  local max="$3"
  local answer

  echo
  read -r -p "${prompt} [default: ${default}]: " answer
  answer="${answer:-${default}}"

  [[ "${answer}" =~ ^[0-9]+$ ]] || die "Selection must be numeric"
  (( answer >= 1 && answer <= max )) || die "Selection out of range"
  printf '%s\n' "${answer}"
}

copy_latest_image() {
  local newest_image
  mkdir -p "${IMAGES_DIR}"
  newest_image="$(find "${SCRIPT_DIR}/output/output/images" -type f -name '*.img' | sort | tail -n1 || true)"
  [[ -n "${newest_image}" ]] || return 0
  cp -f "${newest_image}" "${IMAGES_DIR}/"
  green "Copied image to ${IMAGES_DIR}/$(basename "${newest_image}")"
}

[[ -x "${INTERNAL_BUILD}" ]] || die "Missing internal build script: ${INTERNAL_BUILD}"

echo
green "=== Orange Pi 4 Pro image builder ==="
echo "This workflow is optimized for stability."
echo
echo "System:"
echo "  1) Debian Bullseye (Recommended, tested)"
echo "  2) Ubuntu Jammy (Less tested)"
dist_choice="$(choose_option "Select system" "1" 2)"

echo
echo "TUN support:"
echo "  1) Enable TUN (Recommended if you use sing-box/OpenVPN/tun)"
echo "  2) Disable TUN"
tun_choice="$(choose_option "Select TUN policy" "1" 2)"

echo
echo "Wi-Fi policy:"
echo "  1) Stable LAN + reserve USB Wi-Fi (Recommended)"
echo "     Disables broken onboard AIC8800 and adds ath9k_htc USB Wi-Fi support."
echo "  2) Stock risky Wi-Fi"
echo "     Keeps onboard AIC8800 and does not apply the stable workaround."
wifi_choice="$(choose_option "Select Wi-Fi policy" "1" 2)"

release="bullseye"
tested_note="tested"
case "${dist_choice}" in
  1)
    release="bullseye"
    tested_note="tested"
    ;;
  2)
    release="jammy"
    tested_note="less-tested"
    ;;
esac

tun_policy="disable"
case "${tun_choice}" in
  1) tun_policy="enable" ;;
  2) tun_policy="disable" ;;
esac

image_profile="stock"
aic8800_policy="keep"
usb_wifi_profile="none"
wifi_summary="Stock onboard AIC8800"
case "${wifi_choice}" in
  1)
    image_profile="safe-lan"
    aic8800_policy="disable"
    usb_wifi_profile="ath9k"
    wifi_summary="Disable AIC8800, add ath9k_htc USB Wi-Fi support"
    ;;
  2)
    image_profile="stock"
    aic8800_policy="keep"
    usb_wifi_profile="none"
    wifi_summary="Keep stock onboard AIC8800"
    ;;
esac

echo
yellow "Build summary:"
echo "  System: ${release} (${tested_note})"
echo "  TUN: ${tun_policy}"
echo "  Wi-Fi: ${wifi_summary}"
echo
read -r -p "Start Docker build? Type 'yes' to continue: " confirm
[[ "${confirm}" == "yes" ]] || exit 0

IMAGE_RELEASE="${release}" \
IMAGE_PROFILE="${image_profile}" \
AIC8800_POLICY="${aic8800_policy}" \
USB_WIFI_PROFILE="${usb_wifi_profile}" \
TUN_POLICY="${tun_policy}" \
"${INTERNAL_BUILD}" image

copy_latest_image
