rooted-graphene
===

使用 KernelSU（或 Magisk）修补 GrapheneOS OTA，支持 AVB 验证、锁定 Bootloader **和** Root 权限。  
可通过 [Custota](https://github.com/chenxiaolong/Custota) 和自建 OTA 服务器进行无线升级。  
支持通过 OTA 在 KernelSU root、Magisk root 和 rootless 之间切换。

> ⚠️ **推荐使用 KernelSU**（而非 Magisk），因为它兼容性更好、不易被检测。
> Magisk 的 Zygisk 不支持（而且[大概率永远不会支持](https://github.com/topjohnwu/Magisk/pull/7606)），
> 导致 Magisk 容易被其他应用检测到，大量银行应用无法使用。
> 参见[下方](#使用其他root方案)了解各方案的对比。

## 支持的设备

参见本仓库的 [.github/workflows/release-multiple.yaml](.github/workflows/release-multiple.yaml)。

在 GitHub Action 限制允许的范围内，我会尽量支持更多设备。

如果你想增加设备支持，请向上面的文件提交 PR。  
或者，[自行搭建构建环境](#自行搭建ota构建)会更灵活——你还能拥有自己的签名密钥。

如果这个项目对你有帮助，请考虑 **[向 GrapheneOS 捐赠](https://grapheneos.org/donate)**。  
注意 rooted-graphene 并非 GrapheneOS 官方项目。  
GrapheneOS 团队承担了绝大部分工作，我认为他们值得获得一切支持。

## 重要更新日志

以下仅列出 rooted-graphene 相关的变更，不包括 GrapheneOS 本身的更新。  
GrapheneOS 更新日志请查看 [grapheneos.org/releases](https://grapheneos.org/releases)。

### [#173](https://github.com/schnatterer/rooted-graphene/pull/173)，2025 年 9 月 27 日
Rooted-graphene 选择加入 `stable-security-preview` 频道。

这意味着安全修复可以更快推送，代价是发布时补丁源码不会立即公开。

由于 rooted-graphene 是在原始 OTA 二进制文件上修补而非从源码构建，这一点得以实现。
如果你希望停留在 `stable` 频道，可以轻松[自行搭建构建环境](#自行搭建ota构建)，设置 `OTA_CHANNEL` 为 `stable`。

更多信息：
> 我们可以提供包含这些补丁的早期发布版，并列出 CVE 编号，但在 embargo 结束前不能公开源码或补丁细节。
> 积极的一面是，我们现在可以真正为有需要的人提供补丁，而无需等待之前长达 1 个月的 embargo 延迟。
https://grapheneos.org/releases#2025092500

> 我们认为 security preview 是正常且推荐的选择。
https://grapheneos.social/@GrapheneOS/115272851393143127

### [#141](https://github.com/schnatterer/rooted-graphene/pull/141)，2025 年 7 月 10 日

升级到 Custota 5.12，但该版本存在重大回归：设置无法正确迁移，导致重置。
你需要重新设置 OTA URL 才能获取下一次更新。

[在 Custota 5.13 中修复](https://github.com/chenxiaolong/Custota/blob/v5.13/CHANGELOG.md)，2025 年 7 月 18 日提交 6dc6c4f。

> * 升级到此版本会自动恢复旧设置，无需手动干预。
> * 如果你发现设置已在 5.12 中重置并重新配置了应用，你的新设置不会被影响。

### [#114](https://github.com/schnatterer/rooted-graphene/pull/114)，2025 年 5 月 22 日

升级到 Magisk 29。

Magisk 更新配合 avbroot 可能会出现一个 Bug。

[chenxiaolong/avbroot#455（评论）](https://github.com/chenxiaolong/avbroot/issues/455#issuecomment-2955973508)

包含了一些排查方法。
以下方法对我有效（代价是会重置 Magisk 设置）：
```bash
su -c 'rm -r /data/adb/magisk* && reboot'
```

另见 [rooted-graphene#5](https://github.com/rooted-graphene/ota/issues/5)（上游）。

### 2025032500

OTA 构建迁移到了独立的 GitHub 组织，以获得完整的 GitHub Action 分钟配额。  
借此，可以重新支持[之前停更的设备](#2025030200)了 🥳。

> ⚠️ 你需要在 Custota 应用中更新 OTA 服务器地址为  
> https://warpdotsys.github.io/rooted-graphene/kernelsu（推荐，KernelSU root）  
> 或  
> https://warpdotsys.github.io/rooted-graphene/magisk  
> 或  
> https://warpdotsys.github.io/rooted-graphene/rootless

注意旧的 OTA 服务器地址将不再接收新更新。

更多细节：
* GitHub 组织每月有 2000 分钟免费 Action 额度。
* 每台设备构建约需 10 分钟。
* 每月约 4 次稳定版发布。
* 当前配额足以覆盖现有设备，还有空间支持更多 🥳

### 2025030200

* 停更部分设备（Pixel 8 Pro (husky)、Pixel 8 (shiba)、Pixel 6a (bluejay)），因为维护太多设备所需的 Action 分钟数超出了我的使用额度。
  请 fork 本仓库自行构建 OTA（参见[支持的设备](#支持的设备)）。
  ![image](https://github.com/user-attachments/assets/11cf8fe9-b846-4979-8d7c-723408681354)
* 从 custota 签名文件 v1 切换到 v2（由 [custota 5](https://github.com/chenxiaolong/Custota/blob/v5.0/CHANGELOG.md) 在 2024 年 10 月引入）。
* 如果你还在使用 custota Magisk 模块版本 < 5，请升级。
  更好的做法：直接删除 custota Magisk 模块，因为它现在已内置于 OTA 中。

### 2025021100
* 开始随 OTA 内置 Custota 应用。
* 即使 rootless 也能 OTA 更新，无需你再手动维护 Magisk 模块。
  从下一版本起，你可以通过安装 OTA 更新来切换 root 和 rootless！
* 在 rooted-graphene 的 `-magisk` flavor 中，custota Magisk 模块会在启动时自动禁用。
  你可以安全地删除它。Custota 现在是一个系统应用。
* 在 `-rootless` flavor 中，Custota 是全新安装的，因此没有问题。
  除非你之前在 `-magisk` flavor 中已将 Custota 安装为 Magisk 模块。
  那么你应该先通过 `adb sideload` 安装 `-magisk` 版本，Custota 才能作为系统应用正常工作。
  之后你应该能切换到 `-rootless` 并使用 Custota。
  以下是一些故障排除技巧：
  * 长按 Custota 中的 `Version` 然后选择 `Allow reinstall`，可以测试升级是否正常。
    这样你也可以在 `-magisk` 和 `-rootless` 之间来回切换（只要一切正常运行）。
  * 你可能需要修改所有权或删除以下文件：
    * `/sdcard/Android/data/com.chiller3.custota/`
    * `/data/ota_packagecare_map.pb`
  * 如果你失去了 root 权限，可以随时通过 `adb` 删除模块，参见 [#82](https://github.com/schnatterer/rooted-graphene/issues/82)。

## 首次安装系统

### 提示
* 确保首次安装的未修补版本与你从本仓库下载的版本一致。
* 建议先尝试安装上一个版本，确认 OTA 工作正常后再初始化你的设备。
* 不要混淆 **factory image** 和 OTA。
* 以下步骤基本来自 [avbroot 文档](https://github.com/chenxiaolong/avbroot#initial-setup)，
  使用[本仓库](https://github.com/warpdotsys/rooted-graphene/)的 `avb_pkmd.bin`。

### 安装

⚠️ 刷写设备始终存在一定风险。  
尤其是自 [2025032500](https://github.com/schnatterer/rooted-graphene/issues/89) 首次出现 `Device is corrupt. It can't be trusted` 消息以来。  
关于此错误，我们听到了[多起](https://github.com/schnatterer/rooted-graphene/issues/96#issuecomment-3123443894)[变砖报告](https://github.com/schnatterer/rooted-graphene/issues/96#issuecomment-3358048965)。  
以下步骤应该可以规避此问题。

另外，如果刷写失败，**[不要切换插槽](https://github.com/schnatterer/rooted-graphene/issues/96#issuecomment-3128121844)**。  
仔细阅读[这个 issue](https://github.com/schnatterer/rooted-graphene/issues/96) 中的评论，或寻求帮助。  
如果你的设备无法启动，[这个项目](https://github.com/JoshuaDoes/tensor-usbdl/)可能会有所帮助。

请小心！
我只是提供软件。
你使用它需自行承担风险。

#### 安装 GrapheneOS

##### 网页安装器

网页安装器更简单，但总是安装最新版本。
因此无法立即验证 OTA 升级是否正常工作。

使用[网页安装器](https://grapheneos.org/install/web)安装 GrapheneOS：
* 记下安装的版本号，例如 `Downloaded caiman-install-2024123000.zip release`。
* 在 `Locking the bootloader` 处停下并关闭浏览器。
  稍后我们会锁定 bootloader！

##### 手动安装

网页安装器的替代方法。

下载 [**factory image**](https://grapheneos.org/releases) 并按照[官方说明](https://grapheneos.org/install/cli)安装 GrapheneOS。

**下载 "Install zip" 时，将 URL 的最后一位数字从 `0` 改为 `1`！**

这样你就能直接获得 [security-preview 版本](#173-2025-年-9-月-27-日)，安装后无需切换。

例如从 `https://releases.grapheneos.org/tegu-install-2025122500.zip`  
改为 `https://releases.grapheneos.org/tegu-install-2025122501.zip`

快速指南：

* 启用 OEM 解锁
* 获取最新 `fastboot`
* 解锁 Bootloader：
  启用 USB 调试并执行 `adb reboot bootloader`，或者
  > 最简单的方法是重启设备，然后按住音量减键直到启动进入 bootloader 界面。
   ```shell
   fastboot flashing unlock
   ```
* 刷入 factory image

  ```shell
  bsdtar xvf DEVICE_NAME-factory-VERSION.zip # Windows 和 Mac 上用 tar
  ./flash-all.sh # Windows 上用 .bat
  ````
* 完成后重启（保持 bootloader 解锁状态）

#### 使用本仓库的 OTA 修补 GrapheneOS

安装 GrapheneOS 后

* 从 [releases 页面](https://github.com/warpdotsys/rooted-graphene/releases)下载与已安装版本**相同**的 OTA（末尾 `00` 改为 `01`，参见 [security-preview](#173-2025-年-9-月-27-日)）。
* 获取最新 `fastboot`
* 安装 [avbroot](https://github.com/chenxiaolong/avbroot)
* 从修补后的 OTA 中提取与原版不同的分区镜像。
    ```bash
    avbroot ota extract \
        --input /path/to/ota.zip.patched \
        --directory extracted \
        --fastboot
    ```
* 设置环境变量指向提取目录：

  Linux/macOS：
  ```bash
  export ANDROID_PRODUCT_OUT=extracted
  ```

  Windows（powershell）：
  ```powershell
  $env:ANDROID_PRODUCT_OUT = "extracted"
  ```
  或（bat）：
  ```bat
  set ANDROID_PRODUCT_OUT=extracted
  ```

* 使用以下命令刷写分区：
  ```bash
  fastboot flashall --skip-reboot
  ```
* 在 bootloader 中设置自定义 AVB 公钥。
    ```bash
    fastboot reboot-bootloader
    fastboot erase avb_custom_key
    fastboot flash avb_custom_key avb_pkmd.bin
    ```
* Sideload OTA  
  （避免 `Device is corrupt. It can't be trusted` 错误）
   1. 运行 `fastboot reboot recovery` 进入 recovery 模式。
   2. 你会看到 Android 图标躺倒并显示 "No command"。
      按住电源键，再按一次音量上键，进入 recovery GUI。
   3. 用音量键导航到 "Apply update from ADB"，按电源键确认。
   4. 按照 recovery 提示，使用  
      `adb sideload <path to ota zip>`  
       sideload OTA。
   5. Sideload 完成后，选择重启到 bootloader。
* 如果你使用网页安装器（或手动安装时未使用 security-preview），启动设备后在开机向导中切换到 security-preview 版本。
  然后返回 bootloader（例如使用音量键）。
  参见[公告](#173-2025-年-9-月-27-日)和 [#202](https://github.com/schnatterer/rooted-graphene/issues/202#issuecomment-3620623595) 了解详情。
* 使用以下命令锁定 bootloader。
  这会再次清除数据。
    ```bash
    fastboot flashing lock
    ```
* 按音量减键，再按电源键确认。然后重启。
* 记住：**不要取消勾选 `OEM unlocking`！**（避免[变砖](https://github.com/chenxiaolong/avbroot/blob/v3.12.0/README.md#warnings-and-caveats)）
  即在 Graphene 的开机向导中，保持此框未勾选 👇️
  <img src="https://github.com/schnatterer/rooted-graphene/assets/1824962/6ef90b46-2070-4d08-80d4-5f4a0e749cbe" width="216" height="480" alt="GrapheneOS 建议锁定截图">
  注意：OTA 包含 [OEMUnlockOnBoot](https://github.com/chenxiaolong/OEMUnlockOnBoot)，因此 OEM 锁定应该不可能。
  不过，安全第一，保持解锁。

#### 设置 OTA 更新

* 从设置 → 应用 → 查看所有应用 →（三点菜单）→ 显示系统 →（找到 "System Updater" 应用），[禁用系统更新应用](https://github.com/chenxiaolong/avbroot#ota-updates)（或阻止其网络访问）。
* 打开 Custota 应用，设置 OTA 服务器地址为以下之一：
  * https://warpdotsys.github.io/rooted-graphene/kernelsu （推荐，KernelSU root）
  * https://warpdotsys.github.io/rooted-graphene/magisk （Magisk root）
  * https://warpdotsys.github.io/rooted-graphene/rootless （无 root）

或者你也可以通过 `adb sideload` 手动更新：
* 重启设备，按住音量减键直到进入 bootloader 界面。
* 用音量键切换到 recovery，按电源键确认。
* 如果屏幕卡在 `No command` 界面，按住电源键的同时按一次音量上键。
* 用音量键切换到 `Apply update from ADB`，按电源键确认。
* `adb sideload xyz.zip`。
* 另见[这里](https://github.com/chenxiaolong/avbroot#updates)。

## 在 root 和 rootless 之间切换

三个 flavor 可在 Custota 中随时切换：

| 效果 | Custota URL |
|------|------------|
| **KernelSU root（推荐）** | https://warpdotsys.github.io/rooted-graphene/kernelsu |
| Magisk root | https://warpdotsys.github.io/rooted-graphene/magisk |
| 无 root | https://warpdotsys.github.io/rooted-graphene/rootless |

在 Custota 中修改 URL 后升级即可。
（如果 Custota 提示已是最新版本，长按 `Version` 然后选择 `Allow reinstall` 强制升级）。

## Magisk preinit 参数

参见 [.github/workflows/release-multiple.yaml](.github/workflows/release-multiple.yaml) 中的示例。

如何提取：

* 从 factory image 或 OTA 中获取 boot.img：
  ```shell
     avbroot ota extract \
     --input /path/to/ota.zip \
     --directory . \
     --boot-only
  ```
* 安装 Magisk，修补 boot.img，在输出中找到：  
  `Pre-init storage partition device ID: <name>`
* 或者，从修补后的 boot.img 中提取：
  ```shell
  avbroot boot magisk-info \
  --image magisk_patched-*.img
  ```
* 另见：https://github.com/chenxiaolong/avbroot/blob/master/README.md#magisk-preinit-device

## 自行搭建 OTA 构建

* 生成自己的密钥 `bash -c 'source rooted-ota.sh && generateKeys'`，存放在干燥安全的地方。
* 取消注释或添加你的设备到 `.github/workflows/release-multiple.yaml`
  参见 [Magisk preinit 参数](#magisk-preinit-参数)。

这将设置一个 cron 任务，每晚自动构建最新版 GrapheneOS。

这样你无需太多维护工作，就能拥有自己的签名密钥！
如果你信任第三方 Magisk 包的作者，也可以添加（参见[使用其他 root 方案](#使用其他-root-方案)）。

或者，搜索其他人维护的 fork 中是否有你想要的设备。
但请注意，除了信任[我](https://github.com/schnatterer)、[chenxiaolong](https://github.com/chenxiaolong)（avbroot 和 Custota 的作者）、
Magisk 的作者、GrapheneOS 的作者以及 Android 开源项目的作者之外，你还需要信任 fork 的维护者。

## 脚本

你可以使用本仓库的 `rooted-ota.sh` 脚本自行创建 OTA 并运行自己的 OTA 服务器。

### 仅创建修补后的 OTA

```shell
# 生成密钥
bash -c 'source rooted-ota.sh && generateKeys'

# 交互式输入密码
DEVICE_ID=oriole MAGISK_PREINIT_DEVICE='metadata' bash -c '. rooted-ota.sh && createRootedOta'  
 
# 通过环境变量输入密码（例如 CI 环境）
  export PASSPHRASE_AVB=1
  export PASSPHRASE_OTA=1 
DEVICE_ID=oriole MAGISK_PREINIT_DEVICE='metadata' bash -c '. rooted-ota.sh && createRootedOta' 
```

设备 ID 参见 [grapheneos.org/releases](https://grapheneos.org/releases)。Magisk preinit 参见[这里](#magisk-preinit-参数)。

### 将修补后的 OTA 上传为 GitHub Release 并通过 GH Pages 提供 OTA 服务器

使用 GitHub Actions 自动化：
* [单设备发布](.github/workflows/release-single.yaml)
* [多设备定时发布](.github/workflows/release-multiple.yaml)（使用 cron）

```shell
GITHUB_TOKEN=gh... \
GITHUB_REPO=warpdotsys/rooted-graphene \
DEVICE_ID=oriole \
MAGISK_PREINIT_DEVICE=metadata \
bash -c '. rooted-ota.sh && createAndReleaseRootedOta'
```

### 使用其他 root 方案

由于 [Magisk 似乎与 GrapheneOS 并不完美契合](https://github.com/topjohnwu/Magisk/pull/7606)，你可能在寻找替代方案。

#### KernelSU

本仓库支持使用 [KernelSU](https://kernelsu.org/) 代替 Magisk 构建 OTA。

> ⚠️ **以前的 KernelSU 尝试**导致设备能启动但 root 未授予。这可能是由于：
> - 使用了错误的设备内核 [KMI](https://kernelsu.org/guide/installation.html#kmi)
> - 使用了较旧且不兼容的 KernelSU 工具版本
>
> 当前实现通过以下方式解决这些问题：
> - **自动检测 KMI**：从 boot.img 的内核版本自动识别
> - 使用 **ksud v3.2.1**（最后一个有 Linux 预编译二进制的版本）配合 **最新的 `.ko` 模块**
> - 通过 avbroot 的 `--prepatched` 选项正确签名

要构建 KSU 修补的 OTA，设置 `KSU_VERSION` 环境变量：

```shell
# 使用 KernelSU 构建（KMI 从 boot.img 自动检测）
  export PASSPHRASE_AVB=1 PASSPHRASE_OTA=1
DEVICE_ID=shiba \
KSU_VERSION=v3.2.4 \
MAGISK_PREINIT_DEVICE=sda10 \
bash -c '. rooted-ota.sh && createRootedOta'

# 强制指定 KMI（跳过自动检测）
DEVICE_ID=shiba \
KSU_VERSION=v3.2.4 \
KSU_KMI=android14-6.1 \
MAGISK_PREINIT_DEVICE=sda10 \
bash -c '. rooted-ota.sh && createRootedOta'
```

注意：
- **KSU 需要 rootless OTA 作为基础**（先构建 rootless，然后通过后处理注入 KSU）
- `KSU_KMI` 环境变量可用于手动指定 KMI；未设置时从 boot.img 自动检测
- 设置 `KSU_ALLOW_SHELL=false` 可禁用 shell root 访问

#### 其他替代方案

另一种选择是使用包含 Zygisk 补丁的 Magisk 变体（例如 [pixincreate 维护的版本](https://github.com/pixincreate/Magisk)）。
但仍有一些限制，比如[某些模块检查 Magisk 签名会失败](https://github.com/schnatterer/rooted-graphene/commit/da0cd817c2665798df46df1aeb7caef9d98b79d0#r141746606)。

另一个选择[可能是](https://github.com/schnatterer/rooted-graphene/pull/73#issuecomment-2666870886) Kitsune Magisk。

总的来说，在 GrapheneOS 上使用 [Magisk（尤其是 Zygisk）似乎每次更新都有翻车的风险](https://github.com/chenxiaolong/avbroot/issues/213#issuecomment-1986637884)。
留着 rootless 版本作为备胎总是好的！

## 开发
```bash
# 交互式调试脚本部分功能
DEBUG=1 bash --init-file rooted-ota.sh
# 测试从环境变量加载密钥
PASSPHRASE_AVB=1 PASSPHRASE_OTA=1 bash -c '. rooted-ota.sh && key2base64 && KEY_AVB=doesnotexist createAndReleaseRootedOta'        

# 避免重复下载 OTA：SKIP_CLEANUP=true 或：
mkdir -p .tmp && ln -s $PWD/shiba-ota_update-2023121200.zip .tmp/shiba-ota_update-2023121200.zip

# 仅测试修补
  export PASSPHRASE_AVB=x PASSPHRASE_OTA=y
SKIP_CLEANUP=true DEVICE_ID=oriole MAGISK_PREINIT_DEVICE='metadata' bash -c '. rooted-ota.sh && createRootedOta'

# 测试 KernelSU 修补
  export PASSPHRASE_AVB=x PASSPHRASE_OTA=y
SKIP_CLEANUP=true DEVICE_ID=shiba MAGISK_PREINIT_DEVICE=sda10 KSU_VERSION=v3.2.4 bash -c '. rooted-ota.sh && createRootedOta'

# 仅测试发布
  GITHUB_TOKEN=gh... \
 DEBUG=true \
GITHUB_REPO=warpdotsys/rooted-graphene \
OTA_VERSION=2025021100 \
RELEASE_ID='' \
  bash -c '. rooted-ota.sh && releaseOta'
# 仅测试 GH Pages 部署
GITHUB_REPO=warpdotsys/rooted-graphene \
DEVICE_ID=oriole \
MAGISK_PREINIT_DEVICE=metadata \
  bash -c '. rooted-ota.sh && findLatestVersion && checkBuildNecessary && createOtaServerData && uploadOtaServerData'


# 端到端测试
  GITHUB_TOKEN=gh... \
GITHUB_REPO=warpdotsys/rooted-graphene \
DEVICE_ID=oriole \
MAGISK_PREINIT_DEVICE=metadata \
SKIP_CLEANUP=true \
DEBUG=1 \
  bash -c '. rooted-ota.sh && createAndReleaseRootedOta'
```

## 参考与灵感
https://github.com/MuratovAS/grapheneos-magisk/blob/main/docker/Dockerfile

https://xdaforums.com/t/guide-to-lock-bootloader-while-using-rooted-otaos-magisk-root.4510295/
