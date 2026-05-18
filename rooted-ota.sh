#!/usr/bin/env bash

# 项目根目录绝对路径（供子进程切换工作目录后仍能引用）
_project_root="$(cd "$(dirname "$0")" && pwd)"
readonly PROJECT_ROOT="$_project_root"

# 需要 git、jq 和 curl

KEY_AVB=${KEY_AVB:-avb.key}
KEY_OTA=${KEY_OTA:-ota.key}
CERT_OTA=${CERT_OTA:-ota.crt}
# 或者通过以下环境变量传入（base64 编码）
KEY_AVB_BASE64=${KEY_AVB_BASE64:-''}
KEY_OTA_BASE64=${KEY_OTA_BASE64:-''}
CERT_OTA_BASE64=${CERT_OTA_BASE64:-''}

# 设置以下环境变量可以免交互式输入密码
# PASSPHRASE_AVB
# PASSPHRASE_OTA

# 建议在敏感变量设置完成后再启用 DEBUG，减少泄漏风险
DEBUG=${DEBUG:-''}
if [[ -n "${DEBUG}" ]]; then set -x; fi

# 必填参数
DEVICE_ID=${DEVICE_ID:-} # 设备 ID，参见 https://grapheneos.org/releases
GITHUB_TOKEN=${GITHUB_TOKEN:-''}
GITHUB_REPO=${GITHUB_REPO:-''}

# 可选参数
# 如果要用 Magisk 修补 OTA，请设置你的设备 preinit 分区
MAGISK_PREINIT_DEVICE=${MAGISK_PREINIT_DEVICE:-}
# 设为 "true" 跳过 rootless OTA 的构建
SKIP_ROOTLESS=${SKIP_ROOTLESS:-'false'}
# https://grapheneos.org/releases#stable-channel
OTA_VERSION=${OTA_VERSION:-'latest'}

# Magisk 版本号：默认自动检测最新版，也可通过 MAGISK_VERSION 环境变量指定
# renovate: datasource=github-releases packageName=topjohnwu/Magisk versioning=semver-coerced
MAGISK_VERSION=${MAGISK_VERSION:-auto}

SKIP_CLEANUP=${SKIP_CLEANUP:-''}

# 如果将 gh-pages 克隆到了不同目录，设置此变量指向该目录
PAGES_REPO_FOLDER=${PAGES_REPO_FOLDER:-''}

# 即使 OTA_VERSION 已存在，也将此版本标记为 OTA 服务器上的最新版
FORCE_OTA_SERVER_UPLOAD=${FORCE_OTA_SERVER_UPLOAD:-'false'}
# 强制重新构建并上传产物到 release，即使该版本已有对应 flavor 的产物。
# 这会导致同一个 release 标签下出现多个不同 commit 的制品（不会被 OTA 服务器链接，基本不会被使用）。
# 除了测试构建外，我们希望变更随新版本一起发布，所以重复的制品只是浪费存储。
# 示例：
# shiba-2025020500-3e0add9-rootless.zip
# shiba-2025020500-6718632-rootless.zip
FORCE_BUILD=${FORCE_BUILD:-'false'}
# 跳过将 OTA 服务器上的最新版本指向当前产物（优先级高于 FORCE_OTA_SERVER_UPLOAD）
SKIP_OTA_SERVER_UPLOAD=${SKIP_OTA_SERVER_UPLOAD:-'false'}
# 跳过向 OTA 中注入模块（custota 和 oemunlockonboot）
SKIP_MODULES=${SKIP_MODULES:-'false'}
# 将 OTA 上传到 OTA 服务器的 test 目录
UPLOAD_TEST_OTA=${UPLOAD_TEST_OTA:-false}

# KernelSU 支持：设为版本号（如 'v3.2.4'）或 'latest' 来启用 KSU flavor
KSU_VERSION=${KSU_VERSION:-latest}
# KMI（Kernel Module Interface），留空则自动检测
KSU_KMI=${KSU_KMI:-''}
# 默认允许通过 KernelSU 进行 shell 级 root 访问
KSU_ALLOW_SHELL=${KSU_ALLOW_SHELL:-'true'}
# KernelPatch 版本（用于 kptools-linux / kpimg-android）
KERNELPATCH_VERSION=${KERNELPATCH_VERSION:-'0.13.1'}

OTA_CHANNEL=${OTA_CHANNEL:-stable-security-preview} # 可选: 'stable' 或 'alpha'
NO_COLOR=${NO_COLOR:-''}
OTA_BASE_URL="https://releases.grapheneos.org"

# 以下版本号默认自动检测最新版（通过 GitHub API），失败时回退到注释中的版本号
# 也可以通过环境变量覆盖，如：AVB_ROOT_VERSION=3.29.1
AVB_ROOT_VERSION=${AVB_ROOT_VERSION:-auto}     # 回退: 3.29.1
CUSTOTA_VERSION=${CUSTOTA_VERSION:-auto}       # 回退: 5.22
PATCH_PY_COMMIT=${PATCH_PY_COMMIT:-auto}       # 回退: master 最新 commit
PYTHON_VERSION=${PYTHON_VERSION:-3.14.5-alpine} # Docker Python 镜像标签，手动更新
OEMUNLOCKONBOOT_VERSION=${OEMUNLOCKONBOOT_VERSION:-auto}  # 回退: 1.3
AFSR_VERSION=${AFSR_VERSION:-auto}             # 回退: 1.0.4

CHENXIAOLONG_PK='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDOe6/tBnO7xZhAWXRj3ApUYgn+XZ0wnQiXM8B7tPgv4'
GIT_PUSH_RETRIES=10

set -o nounset -o pipefail -o errexit

# ============================================================
# 自动版本检测函数（将所有写死的依赖改为自动获取最新版）
# ============================================================

# 从 GitHub latest release 获取最新版本号（去掉前导 v）
# 参数: $1 = owner/repo, $2 = 失败时回退的版本号
function fetchLatestGithubTag() {
  local repo="$1" fallback="$2"
  local tag
  tag=$(curl --fail -sL -I -o /dev/null -w '%{url_effective}' "https://github.com/$repo/releases/latest" 2>/dev/null | sed 's/.*\/tag\/v\?//;')
  echo "${tag:-$fallback}"
}

# 从 GitHub 仓库的指定分支获取最新 commit SHA
# 参数: $1 = owner/repo, $2 = 分支名（默认 master）, $3 = 失败时回退的 commit
function fetchLatestCommit() {
  local repo="$1" branch="${2:-master}" fallback="${3:-}"
  local sha
  sha=$(curl --fail -sL "https://api.github.com/repos/$repo/commits/$branch" 2>/dev/null | jq -r '.sha' 2>/dev/null)
  echo "${sha:-$fallback}"
}

# 从缓存恢复工具二进制到 .tmp（如果 .tool-cache/ 存在）
function initToolCache() {
  if [ -d ".tool-cache" ] && [ "$(ls -A .tool-cache 2>/dev/null)" ]; then
    mkdir -p .tmp
    cp -r .tool-cache/* .tmp/
    print "从 .tool-cache 恢复了 $(ls .tool-cache | wc -l) 个工具"
  else
    print "工具缓存不存在，将在线下载"
  fi
}

# 将 .tmp/ 中的工具二进制保存到 .tool-cache/ 供后续构建复用
function saveToolCache() {
  if [ ! -d ".tmp" ]; then printRed "saveToolCache: .tmp 不存在"; return; fi
  mkdir -p .tool-cache
  local count=0
  local tools="avbroot magiskboot ksud ksud.version ksu_module.ko afsr custota-tool"
  for tool in $tools; do
    if [ -f ".tmp/$tool" ]; then
      cp ".tmp/$tool" ".tool-cache/$tool"
      count=$((count + 1))
    fi
  done
  # 缓存 OTA 包（只保留该设备最新一个）
  if [ -n "$OTA_TARGET" ] && [ -f ".tmp/$OTA_TARGET.zip" ]; then
    rm -f ".tool-cache/${DEVICE_ID}-ota-"*.zip
    cp ".tmp/$OTA_TARGET.zip" ".tool-cache/$OTA_TARGET.zip"
    count=$((count + 1))
  fi
  print "已保存 $count 个工具/包到 .tool-cache/"
}

# 解析自动检测标记 "auto"，将 *_VERSION=auto 的变量替换为实际最新版本
# 在脚本各入口函数（createRootedOta, generateKeys 等）中被调用
function initDependencyVersions() {
  [[ "$MAGISK_VERSION" == "auto" ]] && MAGISK_VERSION=$(fetchLatestGithubTag "topjohnwu/Magisk" "v30.7")
  [[ "$AVB_ROOT_VERSION" == "auto" ]] && AVB_ROOT_VERSION=$(fetchLatestGithubTag "chenxiaolong/avbroot" "3.29.1")
  [[ "$CUSTOTA_VERSION" == "auto" ]] && CUSTOTA_VERSION=$(fetchLatestGithubTag "chenxiaolong/Custota" "5.22")
  [[ "$OEMUNLOCKONBOOT_VERSION" == "auto" ]] && OEMUNLOCKONBOOT_VERSION=$(fetchLatestGithubTag "chenxiaolong/OEMUnlockOnBoot" "1.3")
  [[ "$AFSR_VERSION" == "auto" ]] && AFSR_VERSION=$(fetchLatestGithubTag "chenxiaolong/afsr" "1.0.4")
  [[ "$PATCH_PY_COMMIT" == "auto" ]] && PATCH_PY_COMMIT=$(fetchLatestCommit "chenxiaolong/my-avbroot-setup" "master" "84139189c8cbe244a676582a3b3517f31fabc421")

  # 统一规范化 Magisk 版本号：确保始终以 v 开头（GitHub Release tag 格式）
  if [[ -n "$MAGISK_VERSION" ]] && [[ "$MAGISK_VERSION" != v* ]]; then
    MAGISK_VERSION="v${MAGISK_VERSION}"
  fi

  print "已检测依赖版本: Magisk=$MAGISK_VERSION avbroot=$AVB_ROOT_VERSION Custota=$CUSTOTA_VERSION OEMUnlockOnBoot=$OEMUNLOCKONBOOT_VERSION afsr=$AFSR_VERSION"
}

declare -A POTENTIAL_ASSETS

function generateKeys() {
  initDependencyVersions
  downloadAvBroot
  # https://github.com/chenxiaolong/avbroot/tree/077a80f4ce7233b0e93d4a1477d09334af0da246#generating-keys
  # 生成 AVB 和 OTA 签名密钥对
  .tmp/avbroot key generate-key -o $KEY_AVB
  .tmp/avbroot key generate-key -o $KEY_OTA

  # 将 AVB 签名密钥的公钥部分转换为 AVB 公钥元数据格式。
  # 这是 bootloader 设置自定义信任根所需的格式。
  .tmp/avbroot key extract-avb -k $KEY_AVB -o avb_pkmd.bin

  # 为 OTA 签名密钥生成自签名证书。recovery 模式 sideload OTA 时用它验证更新。
  .tmp/avbroot key generate-cert -k $KEY_OTA -o $CERT_OTA

  echo 如有需要，请将以下值上传到 CI 服务器。
  echo 脚本接受以下变量作为环境变量或文件路径
  key2base64
}

function key2base64() {
  KEY_AVB_BASE64=$(base64 -w0 "$KEY_AVB") && echo "KEY_AVB_BASE64=$KEY_AVB_BASE64"
  KEY_OTA_BASE64=$(base64 -w0 "$KEY_OTA") && echo "KEY_OTA_BASE64=$KEY_OTA_BASE64"
  CERT_OTA_BASE64=$(base64 -w0 "$CERT_OTA") && echo "CERT_OTA_BASE64=$CERT_OTA_BASE64"
  export KEY_AVB_BASE64 KEY_OTA_BASE64 CERT_OTA_BASE64
}

function createAndReleaseRootedOta() {
  createRootedOta
  releaseOta

  createOtaServerData
  uploadOtaServerData
}

function createRootedOta() {
  initDependencyVersions
  initToolCache
  [[ "$SKIP_CLEANUP" != 'true' ]] && trap cleanup EXIT ERR

  findLatestVersion
  checkBuildNecessary
  downloadAndroidDependencies
  patchOTAs
  # 构建成功，立即保存工具缓存（此时 .tmp 肯定存在）
  saveToolCache
}

function cleanup() {
  print "正在清理..."
  saveToolCache
  rm -rf .tmp
  unset KEY_AVB_BASE64 KEY_OTA_BASE64 CERT_OTA_BASE64
  print "清理完成。"
}

function checkBuildNecessary() {
  local currentCommit
  currentCommit=$(git rev-parse --short HEAD)
  POTENTIAL_ASSETS=()
    
  # Magisk preinit 分区将在 OTA 下载后从 boot.img 自动检测
  # 如需手动指定，设置 MAGISK_PREINIT_DEVICE 环境变量
  POTENTIAL_ASSETS['magisk']="${DEVICE_ID}-${OTA_VERSION}-${currentCommit}-magisk-${MAGISK_VERSION}$(createAssetSuffix).zip"
  
  
  if [[ "$SKIP_ROOTLESS" != 'true' ]]; then
    POTENTIAL_ASSETS['rootless']="${DEVICE_ID}-${OTA_VERSION}-${currentCommit}-rootless$(createAssetSuffix).zip"
  else
    printGreen "已设置 SKIP_ROOTLESS，跳过 rootless OTA 构建"
  fi

  if [[ -n "$KSU_VERSION" ]]; then
    if [[ "$SKIP_ROOTLESS" == 'true' ]]; then
      printRed "设置了 KSU_VERSION 但 SKIP_ROOTLESS=true —— KSU 需要 rootless OTA 作为基础。终止。"
      exit 1
    fi
    POTENTIAL_ASSETS['ksu']="${DEVICE_ID}-${OTA_VERSION}-${currentCommit}-ksu-${KSU_VERSION}$(createAssetSuffix).zip"
  fi

  RELEASE_ID=''
  local response

  if [[ -z "$GITHUB_REPO" ]]; then print "未设置环境变量 GITHUB_REPO，跳过已存在 release 的检查" && return; fi

  print "潜在 release 版本: ${OTA_VERSION}"

  local params=()
  local url="https://api.github.com/repos/${GITHUB_REPO}/releases"

  if [ -n "${GITHUB_TOKEN}" ]; then
    params+=("-H" "Authorization: token ${GITHUB_TOKEN}")
  fi

  params+=("-H" "Accept: application/vnd.github.v3+json")
  response=$(
    curl --fail -sL "${params[@]}" "${url}" |
      jq --arg release_tag "${OTA_VERSION}" '.[] | select(.tag_name == $release_tag) | {id, tag_name, name, published_at, assets}'
  )

  if [[ -n ${response} ]]; then
    RELEASE_ID=$(echo "${response}" | jq -r '.id')
    print "Release ${OTA_VERSION} 已存在。ID=$RELEASE_ID"
    
    for flavor in "${!POTENTIAL_ASSETS[@]}"; do
      local selectedAsset POTENTIAL_ASSET_NAME="${POTENTIAL_ASSETS[$flavor]}"
      print "检查制品是否已存在: ${POTENTIAL_ASSET_NAME}"
      
      # 严格模式（默认）：包含 commit hash，确保脚本变更后重新构建
      # 宽松模式（CHECK_LENIENT=true）：只按 OTA 版本匹配，适合每日自动构建
      local assetPrefix
      if [[ "${CHECK_LENIENT:-false}" == 'true' ]]; then
        assetPrefix="${DEVICE_ID}-${OTA_VERSION}"
      else
        assetPrefix="${DEVICE_ID}-${OTA_VERSION}-${currentCommit}"
      fi
      selectedAsset=$(echo "${response}" | jq -r --arg assetPrefix "$assetPrefix" \
        '.assets[] | select(.name | startswith($assetPrefix)) | .name' \
          | grep "${flavor}" || true)
  
      if [[ -n "${selectedAsset}" ]] && [[ "$FORCE_BUILD" != 'true' ]] && [[ "$UPLOAD_TEST_OTA" != 'true' ]]; then
        printGreen "跳过构建 '$POTENTIAL_ASSET_NAME'。该 flavor 已存在其他 commit 的产物。" \
          "设置 FORCE_BUILD 或 UPLOAD_TEST_OTA 可强制构建。Release 中已有的产物: ${selectedAsset//$'\n'/ }"
        unset "POTENTIAL_ASSETS[$flavor]"
      else
        print "在 release 中未找到同名产物。"
      fi
    done
    
    if [ "${#POTENTIAL_ASSETS[@]}" -eq 0 ]; then
      printGreen "所有潜在产物均已存在。退出。"
      exit 0
    fi
  else
    print "Release ${OTA_VERSION} 尚未存在。"
  fi
}

function checkMandatoryVariable() {
  for var_name in "$@"; do
    local var_value="${!var_name}"

    if [[ -z "$var_value" ]]; then
      printRed "缺少必填参数 $var_name"
      exit 1
    fi
  done
}

function createAssetSuffix() {
  local suffix=''
  if [[ "${SKIP_MODULES}" == 'true' ]]; then
    suffix+='-minimal'
  fi 
  if [[ "${UPLOAD_TEST_OTA}" == 'true' ]]; then
    suffix+='-test'
  fi
  if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
    suffix+='-dirty'
  fi
  echo "$suffix"
}

function downloadAndroidDependencies() {
  checkMandatoryVariable 'MAGISK_VERSION' 'OTA_TARGET'

  mkdir -p .tmp
  if ! ls ".tmp/magisk-$MAGISK_VERSION.apk" >/dev/null 2>&1 && [[ "${POTENTIAL_ASSETS['magisk']+isset}" ]]; then
    curl --fail -sLo ".tmp/magisk-$MAGISK_VERSION.apk" "https://github.com/topjohnwu/Magisk/releases/download/$MAGISK_VERSION/Magisk-$MAGISK_VERSION.apk"
  fi

  if ! ls ".tmp/$OTA_TARGET.zip" >/dev/null 2>&1; then
    if [[ -n "$PRESEED_OTA_DIR" ]] && [ -f "$PRESEED_OTA_DIR/$OTA_TARGET.zip" ]; then
      cp "$PRESEED_OTA_DIR/$OTA_TARGET.zip" ".tmp/$OTA_TARGET.zip"
      printGreen "从预置目录复制了 OTA: $PRESEED_OTA_DIR/$OTA_TARGET.zip"
    else
      curl --fail -sLo ".tmp/$OTA_TARGET.zip" "$OTA_URL"
    fi
  fi
}

function findLatestVersion() {
  checkMandatoryVariable DEVICE_ID

  # 解析 "latest" 或 "auto" 标记为实际最新版本
  if [[ "$MAGISK_VERSION" == 'latest' ]] || [[ "$MAGISK_VERSION" == 'auto' ]]; then
    MAGISK_VERSION=$(curl --fail -sL -I -o /dev/null -w '%{url_effective}' https://github.com/topjohnwu/Magisk/releases/latest | sed 's/.*\/tag\///;')
    # 规范化：确保以 v 开头
    [[ "$MAGISK_VERSION" != v* ]] && MAGISK_VERSION="v${MAGISK_VERSION}"
  fi
  print "Magisk 版本: $MAGISK_VERSION"

  # 检查 GrapheneOS 最新版本
  # 例如: https://releases.grapheneos.org/shiba-stable

  if [[ "$OTA_VERSION" == 'latest' ]]; then
    OTA_VERSION=$(curl --fail -sL "$OTA_BASE_URL/$DEVICE_ID-$OTA_CHANNEL" | head -n1 | awk '{print $1;}')
  fi
  GRAPHENE_TYPE=${GRAPHENE_TYPE:-'ota_update'} # 另一种选项: factory
  OTA_TARGET="$DEVICE_ID-$GRAPHENE_TYPE-$OTA_VERSION"
  OTA_URL="$OTA_BASE_URL/$OTA_TARGET.zip"
  # 例如: shiba-ota_update-2023121200
  print "OTA 目标: $OTA_TARGET; OTA 下载地址: $OTA_URL"
}

function downloadAvBroot() {
  downloadAndVerifyFromChenxiaolong 'avbroot' "$AVB_ROOT_VERSION"
}

function downloadAndVerifyFromChenxiaolong() {
  local repo="$1"
  local version="$2"
  local artifact="${3:-$1}" # 可选参数: 如果不设置则使用仓库名
  
  local url="https://github.com/chenxiaolong/${repo}/releases/download/v${version}/${artifact}-${version}-x86_64-unknown-linux-gnu.zip"
  local downloadedZipFile
  downloadedZipFile="$(mktemp)"
  
  mkdir -p .tmp

  if ! ls ".tmp/${artifact}" >/dev/null 2>&1; then
    curl --fail -sL "${url}" > "${downloadedZipFile}"
    curl --fail -sL "${url}.sig" > "${downloadedZipFile}.sig"
    
    # 使用作者公钥验证签名
    ssh-keygen -Y verify -I chenxiaolong -f <(echo "chenxiaolong $CHENXIAOLONG_PK") -n file \
      -s "${downloadedZipFile}.sig" < "${downloadedZipFile}"
    
    echo N | unzip "${downloadedZipFile}" -d .tmp
    rm "${downloadedZipFile}"*
    chmod +x ".tmp/${artifact}" # 例如 .tmp/custota-tool
  fi
}

function patchOTAs() {

  downloadAvBroot
  downloadAndVerifyFromChenxiaolong 'afsr' "$AFSR_VERSION"
  if ! ls ".tmp/custota.zip" >/dev/null 2>&1; then
    curl --fail -sL "https://github.com/chenxiaolong/Custota/releases/download/v${CUSTOTA_VERSION}/Custota-${CUSTOTA_VERSION}-release.zip" > .tmp/custota.zip
    curl --fail -sL "https://github.com/chenxiaolong/Custota/releases/download/v${CUSTOTA_VERSION}/Custota-${CUSTOTA_VERSION}-release.zip.sig" > .tmp/custota.zip.sig
  fi
  if ! ls ".tmp/oemunlockonboot.zip" >/dev/null 2>&1; then
    curl --fail -sL "https://github.com/chenxiaolong/OEMUnlockOnBoot/releases/download/v${OEMUNLOCKONBOOT_VERSION}/OEMUnlockOnBoot-${OEMUNLOCKONBOOT_VERSION}-release.zip" > .tmp/oemunlockonboot.zip
    curl --fail -sL "https://github.com/chenxiaolong/OEMUnlockOnBoot/releases/download/v${OEMUNLOCKONBOOT_VERSION}/OEMUnlockOnBoot-${OEMUNLOCKONBOOT_VERSION}-release.zip.sig" > .tmp/oemunlockonboot.zip.sig
  fi
  if ! ls ".tmp/my-avbroot-setup" >/dev/null 2>&1; then
    git clone https://github.com/chenxiaolong/my-avbroot-setup .tmp/my-avbroot-setup
    (cd .tmp/my-avbroot-setup && git checkout ${PATCH_PY_COMMIT})
  fi

  base642key

  # --------------- 从 boot.img 自动检测 KMI 和 Magisk preinit ---------------
  if [[ -z "$KSU_KMI" ]] || [[ -z "$MAGISK_PREINIT_DEVICE" ]]; then
    local otaZip=".tmp/$OTA_TARGET.zip"
    if [ -f "$otaZip" ]; then
      downloadMagiskBoot
      print "正在从 OTA 提取 boot.img 以检测设备参数..."
      local detectDir=".tmp/preinit_detect"
      mkdir -p "$detectDir/boot_extracted"
      .tmp/avbroot ota extract \
        --input "$otaZip" \
        --directory "$detectDir/boot_extracted" \
        --boot-only 2>/dev/null || true
      local bootImg="$detectDir/boot_extracted/boot.img"
      if [ -f "$bootImg" ]; then
        DETECTED_KMI=""
        DETECTED_PREINIT=""
        detectDeviceParams "$bootImg"
        if [[ -z "$KSU_KMI" ]] && [[ -n "$DETECTED_KMI" ]]; then
          KSU_KMI="$DETECTED_KMI"
          printGreen "自动检测到 KSU_KMI: $KSU_KMI"
        fi
        if [[ -z "$MAGISK_PREINIT_DEVICE" ]] && [[ -n "$DETECTED_PREINIT" ]]; then
          MAGISK_PREINIT_DEVICE="$DETECTED_PREINIT"
          printGreen "自动检测到 MAGISK_PREINIT_DEVICE: $MAGISK_PREINIT_DEVICE"
        fi
      else
        printYellow "无法从 OTA 提取 boot.img，将尝试在后续步骤中检测"
      fi
      rm -rf "$detectDir"
    fi
  fi

  # 对 rootless/magisk flavor 执行标准的 Docker 修补流程。
  # KSU 作为后处理步骤单独处理（见下方），在此循环中被跳过。
  for flavor in "${!POTENTIAL_ASSETS[@]}"; do
    if [[ "$flavor" == 'ksu' ]]; then
      continue  # KSU 在 rootless OTA 构建完成后单独处理
    fi

    local targetFile=".tmp/${POTENTIAL_ASSETS[$flavor]}"

    if ls "$targetFile" >/dev/null 2>&1; then
      printGreen "文件 $targetFile 已存在本地，跳过修补。"
    else
      local args=()

      args+=("--output" "$targetFile")
      args+=("--input" ".tmp/$OTA_TARGET.zip")
      args+=("--sign-key-avb" "$KEY_AVB")
      args+=("--sign-key-ota" "$KEY_OTA")
      args+=("--sign-cert-ota" "$CERT_OTA")
      if [[ "$flavor" == 'magisk' ]]; then
        args+=("--patch-arg=--magisk" "--patch-arg" ".tmp/magisk-$MAGISK_VERSION.apk")
        if [[ -n "$MAGISK_PREINIT_DEVICE" ]]; then
          args+=("--patch-arg=--magisk-preinit-device" "--patch-arg" "$MAGISK_PREINIT_DEVICE")
        fi
      fi

      # 如果未设置环境变量，则交互式询问密码
      if [ -v PASSPHRASE_AVB ]; then
        args+=("--pass-avb-env-var" "PASSPHRASE_AVB")
      fi

      if [ -v PASSPHRASE_OTA ]; then
        args+=("--pass-ota-env-var" "PASSPHRASE_OTA")
      fi

      if [[ "${SKIP_MODULES}" != 'true' ]]; then
        args+=("--module-custota" ".tmp/custota.zip")
        args+=("--module-oemunlockonboot" ".tmp/oemunlockonboot.zip")
      fi
      # 稍后会在需要时创建 csig 和设备 JSON 文件
      args+=("--skip-custota-tool")

      # 使用预构建的 Docker 镜像（含 openssh + Python 依赖），跳过每次的 apk add / pip install
      # 如果镜像不存在则回退到原始方法
      local patch_image="rooted-ota-patch:latest"
      if docker image inspect "$patch_image" &>/dev/null; then
        # shellcheck disable=SC2046
        docker run --rm -i $(tty &>/dev/null && echo '-t') -v "$PWD:/app"  -w /app \
          -e PATH='/bin:/usr/local/bin:/sbin:/usr/bin/:/app/.tmp' \
          --env-file <(env) \
          "$patch_image" sh -c \
            "python .tmp/my-avbroot-setup/patch.py ${args[*]} ; result=\$?; \
             chown -R $(id -u):$(id -g) .tmp; exit \$result"
      else
        print "预构建镜像 $patch_image 不存在，回退到 python:${PYTHON_VERSION}"
        # shellcheck disable=SC2046
        docker run --rm -i $(tty &>/dev/null && echo '-t') -v "$PWD:/app"  -w /app \
          -e PATH='/bin:/usr/local/bin:/sbin:/usr/bin/:/app/.tmp' \
          --env-file <(env) \
          "python:${PYTHON_VERSION}" sh -c \
            "apk add openssh && \
             pip install -r .tmp/my-avbroot-setup/requirements.txt && \
             python .tmp/my-avbroot-setup/patch.py ${args[*]} ; result=\$?; \
             chown -R $(id -u):$(id -g) .tmp; exit \$result"
      fi
    
       printGreen "修补完成：${targetFile}"
    fi
    
  done

  # ------------------------------------------------------------------
  # KernelSU 后处理：将 KSU .ko 注入到 rootless OTA 的 boot 中
  # ------------------------------------------------------------------
  if [[ -n "${POTENTIAL_ASSETS['ksu']+isset}" ]]; then
    local rootlessOta=".tmp/${POTENTIAL_ASSETS['rootless']}"
    local ksuTarget=".tmp/${POTENTIAL_ASSETS['ksu']}"

    if ls "$ksuTarget" >/dev/null 2>&1; then
      printGreen "文件 $ksuTarget 已存在本地，跳过修补。"
    elif ls "$rootlessOta" >/dev/null 2>&1; then
      print "正在从 rootless 基础包构建 KSU OTA: $rootlessOta"
      injectKsuIntoOta "$rootlessOta" "$ksuTarget"
    else
      printRed "无法构建 KSU OTA: 未找到 rootless OTA 位于 $rootlessOta"
      exit 1
    fi
  fi
}

# ------------------------------------------------------------------
# KernelSU 相关函数
# ------------------------------------------------------------------

function downloadKsud() {
  local ksudBin=".tmp/ksud"
  local ksuVer="${KSU_VERSION#v}"

  if [ -f "$ksudBin" ] && [ -f ".tmp/ksud.version" ] && [ "$(cat .tmp/ksud.version)" = "$KSU_VERSION" ]; then
    return
  fi

  rm -f "$ksudBin"

  local ksudUrl=""

  # 先尝试从目标 release 获取 ksud
  # KernelSU v3.2.1 是最后一个在 release 中包含预编译 Linux 二进制的版本
  # v3.2.2+ 不再发布 Linux 版本的 ksud 到 release assets
  ksudUrl=$(curl -sL "https://api.github.com/repos/tiann/KernelSU/releases/tags/v${ksuVer}" \
    | python3 -c "
import sys, json
data = json.load(sys.stdin)
for a in data.get('assets', []):
    if 'ksud-x86_64-unknown-linux-musl' in a['name']:
        print(a['browser_download_url'])
        break
" 2>/dev/null)

  if [ -z "$ksudUrl" ]; then
    print "KSU $KSU_VERSION 没有 Linux ksud 二进制。回退到 v3.2.1（最后一个有预编译 ksud 的版本）..."
    ksuVer="3.2.1"
    ksudUrl="https://github.com/tiann/KernelSU/releases/download/v${ksuVer}/ksud-x86_64-unknown-linux-musl"

    # 同时从目标版本下载匹配的 .ko 模块用于注入
    local kmi="${KSU_KMI}"
    if [ -n "$kmi" ]; then
      local koTarget=".tmp/ksu_module.ko"
      print "正在从 KernelSU v${ksuVer} 下载 ${kmi}_kernelsu.ko..."
      curl --fail -sLo "$koTarget" \
        "https://github.com/tiann/KernelSU/releases/download/v${ksuVer}/${kmi}_kernelsu.ko" || {
        printYellow "从 v${ksuVer} 下载 KMI $kmi 的 .ko 失败，将使用内置模块"
        rm -f "$koTarget"
      }
    fi
  fi

  print "正在下载 ksud..."
  curl --fail -sLo "$ksudBin" "$ksudUrl"
  chmod +x "$ksudBin"
  echo "$KSU_VERSION" > ".tmp/ksud.version"
  printGreen "ksud 已下载（来自 ${ksudUrl}）"
}

function downloadMagiskBoot() {
  local magiskbootBin=".tmp/magiskboot"

  if [ -f "$magiskbootBin" ]; then
    return
  fi

  print "正在从 Magisk APK 中提取 magiskboot..."
  local magiskApk=".tmp/magisk-$MAGISK_VERSION.apk"
  if [ ! -f "$magiskApk" ]; then
    print "正在下载 Magisk $MAGISK_VERSION..."
    curl --fail -sLo "$magiskApk" \
      "https://github.com/topjohnwu/Magisk/releases/download/$MAGISK_VERSION/Magisk-$MAGISK_VERSION.apk"
  fi

  python3 -c "
import zipfile, os, stat
with zipfile.ZipFile('$magiskApk') as z:
    z.extract('lib/x86_64/libmagiskboot.so', '.')
os.rename('lib/x86_64/libmagiskboot.so', '$magiskbootBin')
os.chmod('$magiskbootBin', stat.S_IRWXU)
import shutil; shutil.rmtree('lib', ignore_errors=True)
"
  printGreen "magiskboot 提取完成"
}

function detectDeviceParams() {
  local bootImg="$1"
  local kernelVer=""

  # 主方案：使用 magiskboot 解包 boot.img 并自动解压内核
  #
  # 文档依据：
  #   magiskboot unpack（不带 -n 时）默认自动解压所有组件
  #   https://topjohnwu.github.io/Magisk/tools.html#magiskboot
  #   "By default, each component will be automatically decompressed
  #    on-the-fly before writing to the output file."
  #
  # avbroot 也采用相同方法（avbroot/src/patch/boot.rs·get_kmi_version）：
  #   1. 从 boot image 中提取内核数据
  #   2. 自动检测压缩格式并解压（CompressedReader::new(raw_reader, true)）
  #   3. 在解压后的内核中搜索 "Linux version X.Y..." 正则
  #
  # 输出的组件文件名包括: kernel, kernel_dtb, ramdisk.cpio, second, dtb, ...
  # GKI 设备（Pixel 8+）通常输出 kernel_dtb（内核+DTB 合并格式）
  # 传统设备输出 kernel
  local workDir=".tmp/device_detect"
  rm -rf "$workDir"
  mkdir -p "$workDir"
  (cd "$workDir" && ../.tmp/magiskboot unpack "../$bootImg" >/dev/null 2>&1) || true

  local kernelFile=""
  for f in kernel kernel_dtb kernel.gz Image Image.gz Image.lz4; do
    if [ -f "$workDir/$f" ]; then
      kernelFile="$workDir/$f"
      break
    fi
  done

  if [ -n "$kernelFile" ]; then
    # magiskboot 已自动解压，直接读取版本字符串
    kernelVer=$(strings "$kernelFile" | grep -m1 'Linux version [0-9]\+\.[0-9]\+')
  fi
  rm -rf "$workDir"

  if [ -n "$kernelVer" ]; then
    print "内核版本: $kernelVer"
    local major minor
    major=$(echo "$kernelVer" | sed 's/.*Linux version //' | cut -d'.' -f1)
    minor=$(echo "$kernelVer" | sed 's/.*Linux version //' | cut -d'.' -f2)

    case "${major}.${minor}" in
      "5.10") DETECTED_KMI="android12-5.10"; DETECTED_PREINIT="metadata";;
      "5.15") DETECTED_KMI="android13-5.15"; DETECTED_PREINIT="metadata";;
      "6.1")  DETECTED_KMI="android14-6.1";  DETECTED_PREINIT="sda10";;
      "6.6")  DETECTED_KMI="android15-6.6";  DETECTED_PREINIT="sda10";;
      "6.12") DETECTED_KMI="android16-6.12"; DETECTED_PREINIT="sda10";;
      *)
        printRed "未知内核版本 ${major}.${minor}" >&2
        DETECTED_KMI=""; DETECTED_PREINIT=""
        return 1;;
    esac
    printGreen "检测到 KMI: $DETECTED_KMI, preinit: $DETECTED_PREINIT"
    return 0
  fi

  # 回退方案：magiskboot 无法处理该 boot.img 格式，使用设备已知参数
  printYellow "无法从 boot.img 检测内核版本，使用设备已知参数" >&2
  case "${DEVICE_ID}" in
    shiba|husky|felix|tangorpro|akita|caiman|komodo|tokay)
      DETECTED_KMI="android14-6.1"
      DETECTED_PREINIT="sda10"
      ;;
    panther|cheetah|bluejay|lynx|eos)
      DETECTED_KMI="android13-5.15"
      DETECTED_PREINIT="metadata"
      ;;
    *)
      printYellow "未知设备 $DEVICE_ID，使用通用默认值" >&2
      DETECTED_KMI="android14-6.1"
      DETECTED_PREINIT="sda10"
      ;;
  esac
  printYellow "使用设备默认值: KMI=$DETECTED_KMI, preinit=$DETECTED_PREINIT" >&2
  return 0
}

function injectKsuIntoOta() {
  local rootlessOta="$1"
  local ksuTarget="$2"
  local workDir=".tmp/ksu_work"

  print "正在向 OTA 中注入 KernelSU..."
  mkdir -p "$workDir"

  # 1. 确保所需工具已就绪
  downloadAvBroot
  downloadKsud
  downloadMagiskBoot

  # 2. 从 rootless OTA 中提取 boot.img
  print "正在从 rootless OTA 中提取 boot.img..."
  .tmp/avbroot ota extract \
    --input "$rootlessOta" \
    --directory "$workDir/extracted" \
    --boot-only
  printGreen "boot.img 提取完成"

  # 3. 如果未通过环境变量设置 KMI，则自动检测
  local kmi="${KSU_KMI}"
  if [ -z "$kmi" ]; then
    print "正在从 boot.img 自动检测 KMI..."
    DETECTED_KMI=""
    DETECTED_PREINIT=""
    detectDeviceParams "$workDir/extracted/boot.img"
    kmi="$DETECTED_KMI"
    if [ -z "$kmi" ]; then
      printYellow "KMI 自动检测失败，使用设备默认值"
      case "$DEVICE_ID" in
        shiba|husky|akita)  kmi="android14-6.1" ;;  # Pixel 8 系列
        tokay|caiman|komodo) kmi="android15-6.6" ;;  # Pixel 9 系列
        *)                  kmi="android14-6.1" ;;  # 通用回退
      esac
      print "默认 KMI: $kmi"
    else
      printGreen "自动检测到 KMI: $kmi"
    fi
  else
    print "使用已配置的 KMI: $kmi"
  fi

  # 4. 使用 ksud 修补 boot.img
  print "正在用 KernelSU 修补 boot.img（KMI: $kmi）..."
  
  # 前置检查：确认 boot.img 存在且可读
  local bootImgPath="$PROJECT_ROOT/$workDir/extracted/boot.img"
  if [ ! -f "$bootImgPath" ]; then
    printRed "boot.img 不存在于 $bootImgPath"
    ls -la "$PROJECT_ROOT/$workDir/extracted/" 2>/dev/null || true
    exit 1
  fi
  if [ ! -r "$bootImgPath" ]; then
    printRed "boot.img 不可读（权限问题）"
    ls -la "$bootImgPath"
    exit 1
  fi
  
  # ksud 内部会切换工作目录，所有路径必须用绝对路径
  mkdir -p "$workDir/patched"
  local ksudArgs=()
  ksudArgs+=("-b" "$bootImgPath")
  ksudArgs+=("--kmi" "$kmi")
  ksudArgs+=("--magiskboot" "$PROJECT_ROOT/.tmp/magiskboot")
  ksudArgs+=("-o" "$PROJECT_ROOT/$workDir/patched")
  ksudArgs+=("--out-name" "ksu_patched_boot.img")

  # 使用下载的 .ko 模块（如果可用，比 ksud 内置的更新）
  if [ -f "$PROJECT_ROOT/.tmp/ksu_module.ko" ]; then
    print "使用外部 .ko 模块（来自请求的 KSU 版本）"
    ksudArgs+=("--module" "$PROJECT_ROOT/.tmp/ksu_module.ko")
  fi

  if [ "$KSU_ALLOW_SHELL" = 'true' ]; then
    ksudArgs+=("--allow-shell")
  fi

  "$PROJECT_ROOT/.tmp/ksud" boot-patch "${ksudArgs[@]}"

  # 5. 找到修补后的 boot 镜像
  local patchedBoot
  patchedBoot=$(find "$workDir/patched" -maxdepth 1 -type f -name "*.img" 2>/dev/null | head -1)
  if [ -z "$patchedBoot" ]; then
    printRed "在 $workDir/patched 中未找到修补后的 boot 镜像"
    ls -la "$workDir/patched/" 2>/dev/null || true
    exit 1
  fi
  printGreen "KernelSU 修补后的 boot 镜像: $patchedBoot"

  # 6. 使用 avbroot --prepatched 创建 KSU OTA
  print "正在使用预修补的 boot.img 创建签名的 KSU OTA..."
  local avbrootArgs=()
  avbrootArgs+=("ota" "patch")
  avbrootArgs+=("--input" "$rootlessOta")
  avbrootArgs+=("--output" "$ksuTarget")
  avbrootArgs+=("--prepatched" "$patchedBoot")
  avbrootArgs+=("--key-avb" "$KEY_AVB")
  avbrootArgs+=("--key-ota" "$KEY_OTA")
  avbrootArgs+=("--cert-ota" "$CERT_OTA")

  if [ -v PASSPHRASE_AVB ] && [ -n "${PASSPHRASE_AVB+x}" ]; then
    avbrootArgs+=("--pass-avb-env-var" "PASSPHRASE_AVB")
  fi
  if [ -v PASSPHRASE_OTA ] && [ -n "${PASSPHRASE_OTA+x}" ]; then
    avbrootArgs+=("--pass-ota-env-var" "PASSPHRASE_OTA")
  fi

  .tmp/avbroot "${avbrootArgs[@]}"

  # 7. 清理工作目录
  if [ "$SKIP_CLEANUP" != 'true' ]; then
    rm -rf "$workDir"
  fi

  printGreen "KSU OTA created: $ksuTarget"
}

function base642key() {
  set +x # 不让 secrets 出现在日志中
  if [ -n "$KEY_AVB_BASE64" ]; then
    echo "$KEY_AVB_BASE64" | base64 -d >.tmp/$KEY_AVB
    KEY_AVB=.tmp/$KEY_AVB
  fi

  if [ -n "$KEY_OTA_BASE64" ]; then
    echo "$KEY_OTA_BASE64" | base64 -d >.tmp/$KEY_OTA
    KEY_OTA=.tmp/$KEY_OTA
  fi

  if [ -n "$CERT_OTA_BASE64" ]; then
    echo "$CERT_OTA_BASE64" | base64 -d >.tmp/$CERT_OTA
    CERT_OTA=.tmp/$CERT_OTA
  fi

  if [[ -n "${DEBUG}" ]]; then set -x; fi
}

function releaseOta() {

  createReleaseIfNecessary
  
  for flavor in "${!POTENTIAL_ASSETS[@]}"; do
    local assetName="${POTENTIAL_ASSETS[$flavor]}"
    local assetPath=".tmp/$assetName"
    # GitHub Release 单文件限制 ~2GB，超限则跳过
    if [ -f "$assetPath" ] && [ "$(stat -c%s "$assetPath")" -gt 2147483648 ]; then
      printYellow "跳过上传 ${assetName}（文件 >2GB，GitHub Release 不支持）"
      continue
    fi
    uploadFile "$assetPath" "$assetName" "application/zip"
  done
}

function createReleaseIfNecessary() {
  checkMandatoryVariable 'GITHUB_REPO' 'GITHUB_TOKEN'

  local response changelog src_repo current_commit 

  if [[ -z "$RELEASE_ID" ]]; then
    src_repo=$(extractGithubRepo "$(git config --get remote.origin.url)")

    # Security-preview 版本以 01 结尾，但 release 页面锚点链接总是以 00 结尾
    # 例如 25092501 → 25092500
    OTA_VERSION_ANCHOR="${OTA_VERSION/%01/00}"
    if [[ "${GITHUB_REPO}" == "${src_repo}" ]]; then
      changelog=$(curl -sL -X POST -H "Authorization: token $GITHUB_TOKEN" \
        -d "{
                \"tag_name\": \"$OTA_VERSION\",
                \"target_commitish\": \"main\"
              }" \
        "https://api.github.com/repos/$GITHUB_REPO/releases/generate-notes" | jq -r '.body // empty')
      # 替换 \n 为 \\n 保留为字符
      changelog="更新到 [GrapheneOS ${OTA_VERSION}](https://grapheneos.org/releases#${OTA_VERSION_ANCHOR}).\n\n$(echo "${changelog}" | sed ':a;N;$!ba;s/\n/\\n/g')"
    else 
      # 推送到不同仓库的 gh-pages 时，生成 release notes 意义不大，引用源仓库的版本信息即可。
      current_commit=$(git rev-parse --short HEAD)
      changelog="更新到 [GrapheneOS ${OTA_VERSION}](https://grapheneos.org/releases#${OTA_VERSION_ANCHOR}).\n\n由 ${src_repo}@${current_commit} 构建。参见 [更新日志](https://github.com/${src_repo}/blob/${current_commit}/README.md#notable-changelog)。"
    fi
    
    response=$(curl -sL -X POST -H "Authorization: token $GITHUB_TOKEN" \
      -d "{
              \"tag_name\": \"$OTA_VERSION\",
              \"target_commitish\": \"main\",
              \"name\": \"$OTA_VERSION\",
              \"body\": \"${changelog}\"
            }" \
      "https://api.github.com/repos/$GITHUB_REPO/releases")
    RELEASE_ID=$(echo "${response}" | jq -r '.id // empty')
    if [[ -n "${RELEASE_ID}" ]]; then
      printGreen "Release 创建成功，ID: ${RELEASE_ID}"
    elif echo "${response}" | jq -e '.status == "422"' > /dev/null; then
      # 如果 release 在并发构建时已被创建（例如矩阵任务同时跑多个设备）
      RELEASE_ID=$(curl -sL \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
            "https://api.github.com/repos/${GITHUB_REPO}/releases" | \
            jq -r --arg release_tag "${OTA_VERSION}" '.[] | select(.tag_name == $release_tag) | .id // empty')
      if [[ -n "${RELEASE_ID}" ]]; then
        printGreen "无法创建 release，但发现已存在 ${OTA_VERSION} 的 release。ID=$RELEASE_ID"
      else
        printRed "无法创建 release ${OTA_VERSION}：似乎已存在但找不到 ID。"
        exit 1
      fi
    else
      errors=$(echo "${response}" | jq -r '.errors')
      printRed "创建 release ${OTA_VERSION} 失败。错误: ${errors}"
      exit 1
    fi
  fi
}

function uploadFile() {
  local sourceFileName="$1"
  local targetFileName="$2"
  local contentType="$3"
  if [ ! -f "$sourceFileName" ]; then
    printYellow "文件不存在，跳过上传: $sourceFileName"
    return
  fi
  # 注意 --data-binary 可能导致内存溢出
  curl --fail -X POST -H "Authorization: token $GITHUB_TOKEN" \
    -H "Content-Type: $contentType" \
    --upload-file "$sourceFileName" \
    "https://uploads.github.com/repos/$GITHUB_REPO/releases/$RELEASE_ID/assets?name=$targetFileName" || {
    local rc=$?
    printYellow "上传 ${targetFileName} 到 Release 失败（exit $rc），继续执行"
    return
  }
}

function createOtaServerData() {
  downloadCusotaTool

  for flavor in "${!POTENTIAL_ASSETS[@]}"; do
    local POTENTIAL_ASSET_NAME="${POTENTIAL_ASSETS[$flavor]}"
    local targetFile=".tmp/${POTENTIAL_ASSET_NAME}"
    
    local args=()
  
    args+=("--input" "${targetFile}")
    args+=("--output" "${targetFile}.csig")
    args+=("--key" "$KEY_OTA")
    args+=("--cert" "$CERT_OTA")
  
    # 如果未设置环境变量，则交互式询问密码
    if [ -v PASSPHRASE_OTA ]; then
      args+=("--passphrase-env-var" "PASSPHRASE_OTA")
    fi
  
    .tmp/custota-tool gen-csig "${args[@]}"
  
    mkdir -p ".tmp/${flavor}"
    
    local args=()
    args+=("--file" ".tmp/${flavor}/${DEVICE_ID}.json")
    # 例如: https://github.com/schnatterer/rooted-graphene/releases/download/2023121200-v26.4-e54c67f/oriole-ota_update-2023121200.zip
    # 也可以从上传响应中解析下载链接
    args+=("--location" "https://github.com/$GITHUB_REPO/releases/download/$OTA_VERSION/$POTENTIAL_ASSET_NAME")
  
    .tmp/custota-tool gen-update-info "${args[@]}"
  done
}

function downloadCusotaTool() {
  downloadAndVerifyFromChenxiaolong 'Custota' "$CUSTOTA_VERSION" 'custota-tool'
}

function uploadOtaServerData() {

  # 更新 OTA 服务器（GitHub Pages）
  local current_branch current_commit base_dir src_repo
  current_commit=$(git rev-parse --short HEAD)
  folderPrefix=''
  
  if [[ "${UPLOAD_TEST_OTA}" == 'true' ]]; then
    folderPrefix='test/'
  fi

  (
    base_dir="$(pwd)"
    src_repo=$(extractGithubRepo "$(git config --get remote.origin.url)")
    if [[ -n "${PAGES_REPO_FOLDER}" ]]; then
      cd "${PAGES_REPO_FOLDER}"
    fi
    
    current_branch=$(git rev-parse --abbrev-ref HEAD)
    git checkout gh-pages
    
    for flavor in "${!POTENTIAL_ASSETS[@]}"; do
      local POTENTIAL_ASSET_NAME="${POTENTIAL_ASSETS[$flavor]}"
      local targetFile="${folderPrefix}${flavor}/${DEVICE_ID}.json"
  
      uploadFile "${base_dir}/.tmp/${POTENTIAL_ASSET_NAME}.csig" "$POTENTIAL_ASSET_NAME.csig" "application/octet-stream"
      
      mkdir -p "${folderPrefix}${flavor}"
      # 仅当当前 $DEVICE_ID.json 中不包含 $OTA_VERSION 时才更新
      # 我们不希望每次新 commit 或新 Magisk 版本都触发用户升级通知
      # 用户可以通过从 releases 下载 OTA 并 "adb sideload" 来手动升级
      if ! grep -q "$OTA_VERSION" "${targetFile}" || [[ "$FORCE_OTA_SERVER_UPLOAD" == 'true' ]] && [[ "$SKIP_OTA_SERVER_UPLOAD" != 'true' ]]; then
        cp "${base_dir}/.tmp/${flavor}/$DEVICE_ID.json" "${targetFile}"
        git add "${targetFile}"
      elif grep -q "${OTA_VERSION}" "${targetFile}"; then
        printGreen "跳过 OTA 服务器更新，因为 ${OTA_VERSION} 已存在于 ${folderPrefix}${flavor}/${DEVICE_ID}.json 且 FORCE_OTA_SERVER_UPLOAD 未设置。"
      else
        printGreen "跳过 OTA 服务器更新，因为 SKIP_OTA_SERVER_UPLOAD 设为 true。"
      fi
    done
    
    if ! git diff-index --quiet HEAD; then
      # 仅在存在变更时提交和推送
      git config user.name "GitHub Actions" && git config user.email "actions@github.com"
      git commit \
          --message "更新设备 ${DEVICE_ID}，基于 ${src_repo}@${current_commit}" \
    
      gitPushWithRetries
    fi
  
    # 切换回原来的分支
    git checkout "$current_branch"
  )
}

extractGithubRepo() {
  # 同时支持 HTTPS 和 SSH，例如：
  # https://github.com/schnatterer/rooted-graphene
  # git@github.com:schnatterer/rooted-graphene.git

  local remote_url="$1"
  local repo

  # 移除协议前缀和 .git 后缀
  remote_url=$(echo "$remote_url" | sed -e 's/.*:\/\/\|.*@//' -e 's/\.git$//')

  # 提取 owner/repo 部分
  repo=$(echo "$remote_url" | sed -e 's/.*[:\/]\([^\/]*\/[^\/]*\)$/\1/')

  echo "$repo"
}

function gitPushWithRetries() {
  local count=0

  while [ $count -lt $GIT_PUSH_RETRIES ]; do
    git pull --rebase
    if git push origin gh-pages; then
      break
    else
      count=$((count + 1))
      printGreen "重试 $count/$GIT_PUSH_RETRIES 失败。再次重试..."
      sleep 2
    fi
  done
  
  if [ $count -eq $GIT_PUSH_RETRIES ]; then
    printRed "推送 gh-pages 失败，已尝试 $GIT_PUSH_RETRIES 次。"
    exit 1
  fi
}

function print() {
  echo -e "$(date '+%Y-%m-%d %H:%M:%S'): $*"
}

function printGreen() {
  if [[ -z "${NO_COLOR}" ]]; then
    echo -e "\e[32m$(date '+%Y-%m-%d %H:%M:%S'): $*\e[0m"
  else
      print "$@"
  fi
}

function printRed() {
  if [[ -z "${NO_COLOR}" ]]; then
   echo -e "\e[31m$(date '+%Y-%m-%d %H:%M:%S'): $*\e[0m" >&2
  else
      print "$@" >&2
  fi
}

function printYellow() {
  if [[ -z "${NO_COLOR}" ]]; then
    echo -e "\e[33m$(date '+%Y-%m-%d %H:%M:%S'): $*\e[0m"
  else
      print "$@"
  fi
}
