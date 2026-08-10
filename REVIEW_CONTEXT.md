# XD4 构建评审事实库（REVIEW FACTS）

本文件记录本仓库**已验证事实**（实测/排障确认，非推断），供代码评审注入上下文。
评审模型应基于这些事实检查改动是否冲突或遗漏；新增事实时同步更新。

## 产物与格式（2026-08-10 实测）

1. **XD4 固件输出为 `.w` 格式**（ASUS pureubi），不是 `.trx`。两个文件：
   - `3.0.0.4_RTAX56XD4_<rev>_pureubi.w`（主固件）
   - `3.0.0.4_RTAX56XD4_<rev>_cferom_pureubi.w`（仅 bootloader 区，非主固件）
   - WSL2 本地产物 ~17MB；**官方 runner 产物 ~60MB**（UBI 打包差异，大小不影响门禁）
2. **机型标识 `RT-AX56_XD4` 在 runner 产物中不在前 128KB**——质量门/固件校验必须全文搜索（Compute build info 的 grep -a 即全文），检查口径必须一致
3. 文件名不含机型（`RTAX56XD4` 无下划线），不能按文件名匹配机型；机型标识内嵌在固件内容中

## 上游源码事实（SWRT-dev/asuswrt-bcm 386 分支）

4. **asd/prebuild 全机型只有 `asd` 二进制，没有 `libasd.so`**（上游缺失）；asd-install 必须安装 libasd.so → 需从 master 分支同机型 RT-AX56U（同 BCM6755 平台）下载 libasd.so（72472 字节）补齐
5. **runner git clone 偶发未 checkout prebuild/prebuilt 目录内容**（目录存在但空/缺机型子目录，libbcmcrypto/prebuilt.hnd_ax、asd/prebuild 均踩过）→ patch 脚本必须在 Prepare 阶段（.git 未删）无条件 `git checkout HEAD -- <path>` 恢复关键目录
6. asd Makefile 用 `ifeq ($(wildcard $(SRCBASE)/router/asd/*.c),)` 判断走"复制 prebuild"还是"编译"分支——386 分支无 .c 文件走复制分支，`-cp -f` 失败被 `-` 前缀静默吞掉

## 构建环境事实（官方 runner ubuntu-latest）

7. **Build 的 Install host dev libraries 是精简依赖列表**（prep 恢复路径专用）——libtool/libtool-bin/automake/autoconf 曾漏装导致 quagga-install `libtool: No such file or directory`（Error 127）；Prepare 的完整列表已含
8. 官方 runner 根分区 24G（root-reserve 24576MB），编译产物必须放 /workdir 大卷（build-mount-path + workspace 搬迁 symlink）；单 job timeout 上限 360min
9. GitHub cache 单条目上限 10GB、**cache 不可变**（同 key 无法更新）→ 增量产物缓存 Save 必须唯一 key（run_id），Restore 用 restore-keys 前缀匹配；只缓存产物 tar（~433MB）不缓存源码

## 增量构建机制

10. 产物缓存 = `pack_build_artifacts.py` 打包的 `.o/.a/.so/.lo/.ko`（排除 prebuild/prebuilt/.git/dl/image/targets），实测 10854 文件 433MB
11. 增量恢复三要素：产物时间戳比源码新（touch 到 NOW-60s，绝不 touch 源码/Makefile/configure）、失败组件产物删除强制重编（排除 prebuild/，误删导致 "No rule to make target 'private.c'"）、key 只含 source_rev（AI fix 改 patch 后 make 时间戳自动重编受影响组件）
12. 失败组件定位：error-log 里 `### 失败组件: XXX ###` 行；收集最近 3 次失败去重

## 触发链

13. Build 不监听 schedule/repository_dispatch；上游更新 → update_checker → repository_dispatch 触发 Prepare（打包新源码）→ workflow_run 自动触发 Build
14. Build 的 Prep 环境恢复校验：softcenter（Softcenter.asp + softcenter.sh）必须存在，prep-env.tgz 解压失败禁止静默吞错
