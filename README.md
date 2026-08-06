# AutoBuild_Merlin_for_ZenWiFi_XD4

给华硕 **ZenWiFi XD4** 自动编译 **梅林固件（内置软件中心）** 的 GitHub Actions 项目。

## 固件特性

- 基于 [SWRT-dev/asuswrt-bcm](https://github.com/SWRT-dev/asuswrt-bcm)（梅林 MerlinR 系列，koolshare 软件中心生态的延续）
- **386 分支**：与 ZenWiFi XD4 官方固件线（3.0.0.4.386_xxxxx）同代，和你路由器当前的 Koolcenter 386 固件同线
- **内置软件中心（softcenter）**：刷机后即可安装第三方插件（fancyss 科学上网、aria2、ddns 等）
- XD4 专用配置构建（`947622GW.RT-AX56_XD4`，`BRCM_BOARD_ID="XD4"`）
- 全自动：上游更新检测 → 编译 → 质量门 → 发布 Release → 旧版本清理

## 支持的机型

| 机型 | make 目标 | 说明 |
|---|---|---|
| ZenWiFi XD4 | `rt-ax56_xd4` | 默认，XD4 专用 Board ID |
| RT-AX56U | `rt-ax56u` | 同平台（BCM6755），可用同一固件线 |

> 同平台的 RT-AX55、TUF-AX3000 等机型未列入，如需支持可自行在 workflow_dispatch 中传入对应 make 目标。

## 使用方法

### 1. 手动构建

仓库页面 → **Actions** → **Build Merlin Firmware for ZenWiFi XD4** → **Run workflow**：

- `model`: 构建目标（默认 `rt-ax56_xd4`）
- `branch`: 上游分支（默认 `386`）

### 2. 自动构建

- **每 12 小时**检查一次上游 `386` 分支，有更新才触发构建（无更新时跳过，不消耗构建时长）
- 推送修改 `.github/workflows/` 或 `custom_scripts/` 也会触发

### 3. 获取固件

构建成功后会自动：

1. 上传 **Artifact**（保留 14 天）
2. 发布 **Release**（tag 形如 `Merlin_XD4_RT-AX56_XD4_3.0.0.4_386_xxx_<run>`）
3. 自动清理旧 Release，只保留最近 3 个

固件文件：`RT-AX56_XD4_3.0.0.4_386_xxx.trx` + `.sha256` 校验文件 + `firmware-info.txt` 构建信息。

## 刷机步骤

1. 下载 `.trx` 固件，用 `sha256sum`（Windows 可用 `certutil -hashfile`）核对 SHA256
2. 浏览器登录路由器管理页（192.168.50.1）→ **系统管理** → **固件升级**
3. 选择 `.trx` 文件，等待升级完成（约 5 分钟，期间不要断电）
4. 升级后建议 **恢复出厂设置**（系统管理 → 恢复/导出/上传设置 → 恢复原厂默认值），避免旧配置残留问题

> ⚠️ 刷机有风险！请确保已备份当前配置。跨版本降级可能损坏配置分区。

## 软件中心使用

固件内置软件中心，刷机后：

1. 登录路由器 → 左侧菜单出现 **软件中心**
2. 首次使用点击 **软件中心更新** 升级到最新版本
3. 在插件列表中安装所需插件（fancyss 等），或使用 **离线安装** 上传 `.tar.gz` 插件包

插件兼容性：软件中心采用 armv7l + FPU 架构（BCM675x），与 koolshare 梅林改版 386 系插件兼容。

## 构建原理

| 组件 | 来源 |
|---|---|
| 固件源码 | `SWRT-dev/asuswrt-bcm` 分支 `386`（含软件中心 `release/src/router/softcenter/`） |
| 工具链 | `SWRT-dev/bcmhnd-toolchains` + `SWRT-dev/bcm-toolchains`（`/opt/toolchains`） |
| 构建环境 | Ubuntu 24.04 + swrt-docker 同款依赖清单 |
| 构建命令 | `cd release/src-rt-5.02axhnd.675x && make rt-ax56_xd4` |

### 质量门（发布前强制检查）

`custom_scripts/validate_build_output.py --gate`：

1. 固件文件存在且文件名含 `RT-AX56_XD4`
2. 固件大小 ≥ 10 MB
3. 软件中心源码存在（`release/src/router/softcenter/Softcenter.asp` + `softcenter.sh`）

质量门未通过 → 不发布 Release、不生成固件产物。

## 目录结构

```
├── .github/workflows/
│   ├── Build_Merlin_Firmware.yml   # 主构建工作流
│   └── cleanup-workflow-runs.yml   # 每日清理 workflow 运行记录
├── custom_scripts/
│   ├── validate_build_output.py    # 构建质量门
│   ├── cleanup_releases.py         # 旧 Release 清理（保留 N 个）
│   ├── cleanup_workflow_runs.py    # workflow 运行记录清理
│   └── extract_last_error.py       # 构建失败错误日志提取
└── README.md
```

## 设计参考（吸收自 Fatty911 其他仓库）

- `AutoBuild_OpenWrt_for_XiaoMi_R4`：构建质量门、Release 自动发布 + 旧版本清理、上游更新检查、失败错误日志提取、磁盘空间最大化、依赖缓存
- `LEDE_Multi_Device_Build` / `CustomOpenWrtImageBuilder`：workflow_dispatch 输入参数化模型选择
- 上游 `SWRT-dev/asuswrt-bcm` 自身 CI：容器/工具链环境配方

## 致谢与声明

- [RMerl/asuswrt-merlin.ng](https://github.com/RMerl/asuswrt-merlin.ng)：Asuswrt-Merlin 官方项目
- [SWRT-dev/asuswrt-bcm](https://github.com/SWRT-dev/asuswrt-bcm)：梅林改版（含软件中心）源码
- [koolshare / koolcenter](https://www.asusgo.com)：软件中心生态

本仓库仅自动化编译，固件版权归原作者所有。仅供个人学习研究使用，刷机风险自负。
