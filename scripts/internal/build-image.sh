#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-image}"
shift || true
EXTRA_ARGS=("$@")

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
WORKSPACE_DIR="$(cd "${PROJECT_DIR}/.." && pwd)"
BUILD_DIR="${WORKSPACE_DIR}/orangepi-build"
CONTAINER_IMAGE="${CONTAINER_IMAGE:-ubuntu:22.04}"
SRC_VOLUME="orangepi-build-src"
ARTIFACTS_DIR="${PROJECT_DIR}/output"
KERNEL_CONFIG_NAME="linux-sun60iw2-legacy-a733"
DOCKER_PLATFORM="${DOCKER_PLATFORM:-linux/arm64}"
IMAGE_RELEASE_DEFAULT="${IMAGE_RELEASE:-jammy}"
IMAGE_PROFILE="${IMAGE_PROFILE:-safe-lan}"
AIC8800_POLICY="${AIC8800_POLICY:-auto}"
USB_WIFI_PROFILE="${USB_WIFI_PROFILE:-none}"
TUN_POLICY="${TUN_POLICY:-enable}"
PROJECT_MOUNT="/host-project"
HOST_SRC_MOUNT="/host-src"

if ! command -v docker >/dev/null 2>&1; then
  echo "Error: docker not found in PATH"
  exit 1
fi

mkdir -p "${ARTIFACTS_DIR}"

BUILD_ARGS=(BOARD=orangepi4pro BRANCH=legacy KERNEL_CONFIGURE=no)
EXTRA_RELEASE_SET="no"
for arg in "${EXTRA_ARGS[@]}"; do
  if [[ "${arg}" == RELEASE=* ]]; then
    EXTRA_RELEASE_SET="yes"
    break
  fi
done

case "${MODE}" in
  kernel)
    BUILD_ARGS+=(BUILD_OPT=kernel)
    RESULT_HINT="Kernel deb packages: ${ARTIFACTS_DIR}/output/debs/"
    ;;
  image)
    BUILD_ARGS+=(BUILD_OPT=image BUILD_DESKTOP=no BUILD_MINIMAL=no)
    if [[ "${EXTRA_RELEASE_SET}" == "no" ]]; then
      BUILD_ARGS+=("RELEASE=${IMAGE_RELEASE_DEFAULT}")
    fi
    RESULT_HINT="Full image: ${ARTIFACTS_DIR}/output/images/"
    ;;
  *)
    echo "Error: unknown mode '${MODE}'"
    echo "Usage: $0 [image|kernel] [extra build args...]"
    exit 1
    ;;
esac

if [[ "${MODE}" == "image" ]]; then
  cleaned_extra_args=()
  found_clean_level="no"
  for arg in "${EXTRA_ARGS[@]}"; do
    if [[ "${arg}" == CLEAN_LEVEL=* ]]; then
      found_clean_level="yes"
      level="${arg#CLEAN_LEVEL=}"
      level="${level//alldebs/}"
      level="${level//debs/}"
      level="${level//,,/,}"
      level="${level#,}"
      level="${level%,}"
      [[ -z "${level}" ]] && level="make,oldcache"
      cleaned_extra_args+=("CLEAN_LEVEL=${level}")
    else
      cleaned_extra_args+=("${arg}")
    fi
  done
  if [[ "${found_clean_level}" == "no" ]]; then
    cleaned_extra_args+=("CLEAN_LEVEL=make,oldcache")
  fi
  EXTRA_ARGS=("${cleaned_extra_args[@]}")
fi

BUILD_ARGS_STR=""
for arg in "${BUILD_ARGS[@]}" "${EXTRA_ARGS[@]}"; do
  BUILD_ARGS_STR+=" $(printf '%q' "${arg}")"
done

echo "[1/3] Preparing container image: ${CONTAINER_IMAGE}"
docker pull --platform "${DOCKER_PLATFORM}" "${CONTAINER_IMAGE}" >/dev/null

echo "[2/3] Running orangepi-build inside Docker (${MODE})"
echo "      Using Docker volume '${SRC_VOLUME}' to avoid macOS case-insensitive FS issues."
echo "      Docker platform: ${DOCKER_PLATFORM}"
docker volume create "${SRC_VOLUME}" >/dev/null

DOCKER_RUN_ARGS=(
  --platform "${DOCKER_PLATFORM}"
  --rm
  -i
  --entrypoint /bin/bash
  -v "${SRC_VOLUME}:/work"
  -v "${ARTIFACTS_DIR}:/host-out"
  -v "${PROJECT_DIR}:${PROJECT_MOUNT}:ro"
  -v orangepi-cache:/work/cache
  -v orangepi-ccache:/root/.ccache
  -e AIC8800_POLICY="${AIC8800_POLICY}"
  -e USB_WIFI_PROFILE="${USB_WIFI_PROFILE}"
  -e TUN_POLICY="${TUN_POLICY}"
  -e BUILD_MODE="${MODE}"
  -e IMAGE_PROFILE="${IMAGE_PROFILE}"
  -e KERNEL_CONFIG_NAME="${KERNEL_CONFIG_NAME}"
  -e BUILD_ARGS_STR="${BUILD_ARGS_STR}"
)

if [[ -d "${BUILD_DIR}" ]]; then
  DOCKER_RUN_ARGS+=(-v "${BUILD_DIR}:${HOST_SRC_MOUNT}:ro")
fi

if [[ "${MODE}" == "image" ]]; then
  DOCKER_RUN_ARGS+=(
    --privileged
    --security-opt apparmor:unconfined
    --cap-add SYS_ADMIN
    --cap-add MKNOD
    --cap-add SYS_PTRACE
    "--device-cgroup-rule=b 7:* rmw"
    "--device-cgroup-rule=b 259:* rmw"
    -v /dev:/tmp/dev:ro
  )
fi

docker run "${DOCKER_RUN_ARGS[@]}" \
  "${CONTAINER_IMAGE}" -s <<'CONTAINER_SCRIPT'
set -euo pipefail

if ! command -v git >/dev/null 2>&1; then
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    git sudo systemd systemd-container locales ca-certificates curl gnupg \
    gawk dialog rsync xz-utils fdisk util-linux parted dosfstools kmod
  locale-gen en_US.UTF-8 >/dev/null 2>&1 || true
fi

if [[ ! -d /work/.git ]]; then
  if [[ -d /host-src/.git ]]; then
    rsync -a --delete /host-src/ /work/
  else
    git clone --depth=1 https://github.com/orangepi-xunlong/orangepi-build /tmp/orangepi-build
    shopt -s dotglob
    mv /tmp/orangepi-build/* /work/
    rm -rf /tmp/orangepi-build
  fi
fi

cd /work
mkdir -p userpatches

if [[ -d /host-out/output/debs ]]; then
  mkdir -p /work/output
  cp -a /host-out/output/debs /work/output/ 2>/dev/null || true
fi

export SKIP_EXTERNAL_TOOLCHAINS='yes'

if ! command -v arm-linux-gnueabi-gcc >/dev/null 2>&1 || ! command -v aarch64-linux-gnu-gcc >/dev/null 2>&1; then
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    gcc-arm-linux-gnueabi gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu
fi

for tool in gcc g++ cpp ar as ld nm objcopy objdump ranlib readelf strip; do
  if command -v "aarch64-linux-gnu-${tool}" >/dev/null 2>&1 && ! command -v "aarch64-none-linux-gnu-${tool}" >/dev/null 2>&1; then
    ln -sf "$(command -v "aarch64-linux-gnu-${tool}")" "/usr/local/bin/aarch64-none-linux-gnu-${tool}"
  fi
done

host_arch=$(dpkg --print-architecture)
for dtcbin in /work/u-boot/*/scripts/dtc/dtc; do
  [[ -f "$dtcbin" ]] || continue
  if [[ "$host_arch" == "arm64" ]] && readelf -h "$dtcbin" 2>/dev/null | grep -q 'Machine:.*X86-64'; then
    stale_uboot_dir=$(echo "$dtcbin" | sed 's#/scripts/dtc/dtc$##')
    echo "Detected stale x86_64 u-boot host tool: $dtcbin"
    echo "Removing stale u-boot tree: $stale_uboot_dir"
    rm -rf "$stale_uboot_dir"
  fi
done

if [[ ! -f "userpatches/${KERNEL_CONFIG_NAME}.config" ]]; then
  cp "external/config/kernel/${KERNEL_CONFIG_NAME}.config" "userpatches/${KERNEL_CONFIG_NAME}.config"
fi

set_kconfig_tristate() {
  local symbol="$1"
  local value="$2"
  local file="userpatches/${KERNEL_CONFIG_NAME}.config"

  sed -i -E "/^${symbol}=|^# ${symbol} is not set$/d" "${file}"

  case "${value}" in
    y|m)
      printf '%s=%s\n' "${symbol}" "${value}" >> "${file}"
      ;;
    n)
      printf '# %s is not set\n' "${symbol}" >> "${file}"
      ;;
    *)
      echo "Unsupported tristate value for ${symbol}: ${value}" >&2
      exit 1
      ;;
  esac
}

if [[ "${TUN_POLICY}" == "enable" ]]; then
  set_kconfig_tristate CONFIG_TUN m
else
  set_kconfig_tristate CONFIG_TUN n
fi

disable_aic8800="no"
if [[ "${AIC8800_POLICY}" == "disable" ]]; then
  disable_aic8800="yes"
elif [[ "${AIC8800_POLICY}" == "auto" && "${BUILD_MODE}" == "image" && "${IMAGE_PROFILE}" != "stock" && "${IMAGE_PROFILE}" != "off" ]]; then
  disable_aic8800="yes"
fi

if [[ "${disable_aic8800}" == "yes" ]]; then
  for sym in \
    CONFIG_AIC8800_WLAN_SUPPORT \
    CONFIG_AIC8800_BTLPM_SUPPORT \
    CONFIG_AIC_WLAN_SUPPORT \
    CONFIG_AIC_INTF_SDIO
  do
    if grep -q "^${sym}=" "userpatches/${KERNEL_CONFIG_NAME}.config"; then
      sed -i -E "s/^${sym}=.*/# ${sym} is not set/" "userpatches/${KERNEL_CONFIG_NAME}.config"
    elif ! grep -q "^# ${sym} is not set$" "userpatches/${KERNEL_CONFIG_NAME}.config"; then
      printf '# %s is not set\n' "${sym}" >> "userpatches/${KERNEL_CONFIG_NAME}.config"
    fi
  done
fi

case "${USB_WIFI_PROFILE}" in
  none)
    ;;
  ath9k)
    for sym in \
      CONFIG_ATH9K_HW \
      CONFIG_ATH9K_COMMON \
      CONFIG_ATH9K_HTC
    do
      set_kconfig_tristate "${sym}" m
    done
    ;;
  *)
    echo "Unsupported USB_WIFI_PROFILE: ${USB_WIFI_PROFILE}" >&2
    exit 1
    ;;
esac

export KCFLAGS='-Wno-error'
export HOSTCFLAGS='-Wno-error'
export DTC='/usr/bin/dtc'

set +e
eval "./build.sh ${BUILD_ARGS_STR}"
rc=$?
set -e

if [[ "$rc" -eq 0 && "${BUILD_MODE}" == "image" && "${IMAGE_PROFILE}" != "stock" && "${IMAGE_PROFILE}" != "off" ]]; then
  while IFS= read -r image_path; do
    [[ -n "${image_path}" ]] || continue
    "${PROJECT_MOUNT}/scripts/postprocess-image-safe-lan.sh" "${image_path}"
  done < <(find output/images -type f -name '*.img' | sort)
fi

rm -rf /host-out/output
cp -a output /host-out/
cp -a "userpatches/${KERNEL_CONFIG_NAME}.config" /host-out/

exit $rc
CONTAINER_SCRIPT

echo "[3/3] Done"
echo "${RESULT_HINT}"
echo "Check TUN line:"
echo "grep -n '^CONFIG_TUN\\|^# CONFIG_TUN' ${ARTIFACTS_DIR}/${KERNEL_CONFIG_NAME}.config"
