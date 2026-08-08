#!/bin/bash
# 给 SWRT-dev/asuswrt-bcm 386 分支补上 XD4 / RT-AX56U 模型定义。
#
# 背景: 386 分支的 buildtools/target.mak.3004 只定义了 RT-AX55 的模型变量，
# 而 save_src_config 要求模型变量存在 (RT-AX56_XD4)，否则报 "NO THIS TARGET"。
# 完整模型表在 24353/master 分支 (release/src-rt/target.mak, 163 个模型变量)。
# 本脚本从 24353 分支逐字注入 XD4/RT-AX56U 定义（同平台 947622GW/BCM47622），
# 并补上 24353 定义中缺失的 SWRT_NAME/SWRT_VER_MAJOR/SWRT_VER_MINOR
# （router/Makefile:196 的 export $(SWRT_NAME)=y 需要 SWRT_NAME 非空），
# 使 386 分支也能构建 XD4 专用配置 (BRCM_BOARD_ID="XD4")。
set -euo pipefail

REPO_DIR="${1:?用法: patch_xd4_source.sh <asuswrt-bcm 目录>}"
cd "$REPO_DIR"

TARGET_MAK="buildtools/target.mak.3004"

if grep -q "RT-AX56_XD4 :=" "$TARGET_MAK"; then
  echo "✅ RT-AX56_XD4 已定义，跳过注入"
else
  echo "=== 注入 XD4/RT-AX56U 模型定义到 $TARGET_MAK ==="
  cat >> "$TARGET_MAK" <<'SWRT_EOF'
  # === AutoBuild_Merlin_for_ZenWiFi_XD4 注入的模型定义 (取自 24353 分支 release/src-rt/target.mak) ===
  # 注意: 386 分支模型定义无 BT_CONN 变量 (bluez 不启用 extaqis, 因为 386 源码树
  # 没有 bleencrypt/gatt-amap.h; 24353 分支的 BT_CONN=y 会导致 bluez configure
  # --enable-extaqis 编译 aqis profile 时找不到头文件, 故此处统一去掉 BT_CONN)。
export HND-947622_BASE := HND_ROUTER=y HND_ROUTER_AX_675X=y PROFILE="947622GW" SAMBA3="3.6.x" OOKLA=y WL_SCHED_V3=y CABLEDIAG=y SOFTCENTER=y UBI=y UBIFS=y PSISTLOG=y SMARTDNS=y CIFS=y SWRT=y ENTWARE=y CAPTCHA=y
export HND-947622_BASE_NOUSB := HND_ROUTER=y HND_ROUTER_AX_675X=y PROFILE="947622GW" WL_SCHED_V3=y OOKLA=y CABLEDIAG=y SOFTCENTER=y UBI=y UBIFS=y PSISTLOG=y SMARTDNS=y CIFS=y SWRT=y CAPTCHA=y
export RT-AX56_XD4 := $(HND-947622_BASE_NOUSB)
export RT-AX56_XD4 += BUILD_NAME="RT-AX56_XD4" NVSIZE="128" DHDAP=y HND_WL=y DPSTA=y LACP=n WTFAST=n REPEATER=y DISABLE_REPEATER_UI=y DISABLE_PROXYSTA_UI=y IPV6SUPP=y HTTPS=y ARM=y AUTODICT=y BBEXTRAS=y USBEXTRAS=y EBTABLES=y MEDIASRV=n MODEM=n PARENTAL2=y ACCEL_PPTPD=y PRINTER=n WEBDAV=n SMARTSYNCBASE=n USB="USB" APP="none" PROXYSTA=y DNSMQ=y SHP=n BCMWL6=y BCMWL6A=y DISK_MONITOR=n BTN_WIFITOG=n OPTIMIZE_XBOX=y ODMPID=y LED_BTN=n BCMSMP=y XHCI=n DUALWAN=n  NEW_USER_LOW_RSSI=y OPENVPN=y TIMEMACHINE=n MDNS=y VPNC=y BRCM_NAND_JFFS2=y JFFS2LOG=y BWDPI=y DUMP_OOPS_MSG=n LINUX_MTD="64" DEBUGFS=y TEMPROOTFS=n SSH=y EMAIL=y FRS_FEEDBACK=y SYSSTATE=y ROG=n STAINFO=y CLOUDCHECK=n NATNL_AICLOUD=n REBOOT_SCHEDULE=y MULTICASTIPTV=y QUAGGA=y WLCLMLOAD=n BCM_MUMIMO=y LAN50="all" ATCOVER=y GETREALIP=y CFEZ=y ETLAN_LED=n TFAT=n NTFS="" HFS="" NEWSSID_REV2=y NEWSSID_REV4=y NEWSSID_REV5=y NEW_APP_ARM=y VISUALIZATION=n BONDING=n BONDING_WAN=n NETOOL=y TRACEROUTE=y FORCE_AUTO_UPGRADE=y ALEXA=y IFTTT=y SW_HW_AUTH=y ASPMD=n BCM_MEVENT=n BCM_APPEVENTD=n LETSENCRYPT=y VPN_FUSION=y JFFS_NVRAM=y NVRAM_ENCRYPT=y IPSEC=STRONGSWAN IPSEC_SRVCLI_ONLY=SRV NATNL_AIHOME=n BCM_CEVENTD=y UTF8_SSID=y AMAS=y DWB=y DBLOG=y ETHOBD=y CONNDIAG=y NFCM=n CRASHLOG=y WATCH_REINIT=y BW160M=n BRCM_HOSTAPD=y TCPLUGIN=y UUPLUGIN=y IPERF3=y INFO_EXAP=y FRS_LIVE_UPDATE=y AVBLCHAN=y NO_SAMBA=y NO_FTP=y NO_USBSTORAGE=y BCM_CLED=y SINGLE_LED=y BHCOST_OPT=y AMAS_WGN=y AMAZON_WSS=y AHS=y ASD=y INTERNETCTRL=y SW_CTRL_ALLLED=y HSPOT=y BCN_RPT=y BTM_11V=y BCMEVENTD=y PORT2_DEVICE=y URLFW=y AMAS_SYNC_2G_BW=y INSTANT_GUARD=y AMAS_ETHDETECT=y ACL96=y IPV6S46=y OCNVC=y GOOGLE_ASST=y ASUSCTRL=y WIREGUARD=y CALC_NVRAM=y COMFW=y SWRT_VER_MAJOR="R" SWRT_VER_MINOR="5.2.9" SWRT_NAME="RTAX56XD4"
export RT-AX56U := $(HND-947622_BASE)
export RT-AX56U += BUILD_NAME="RT-AX56U" SWITCH2="BCM53134" NVSIZE="128" DHDAP=y HND_WL=y DPSTA=y LACP=n WTFAST=n REPEATER=y IPV6SUPP=y HTTPS=y ARM=y AUTODICT=y BBEXTRAS=y USBEXTRAS=y EBTABLES=y MEDIASRV=y MODEM=y USB_WAN_BACKUP=y PARENTAL2=y ACCEL_PPTPD=y PRINTER=y WEBDAV=y SMARTSYNCBASE=y USB="USB" APP="network" PROXYSTA=y DNSMQ=y SHP=n BCMWL6=y BCMWL6A=y DISK_MONITOR=y BTN_WIFITOG=n OPTIMIZE_XBOX=y ODMPID=y LED_BTN=n BCMSMP=y XHCI=y DUALWAN=y  NEW_USER_LOW_RSSI=y OPENVPN=y TIMEMACHINE=y MDNS=y VPNC=y BRCM_NAND_JFFS2=n JFFS2LOG=n BWDPI=y DUMP_OOPS_MSG=n LINUX_MTD="64" DEBUGFS=y TEMPROOTFS=n SSH=y EMAIL=y FRS_FEEDBACK=y SYSSTATE=y ROG=n STAINFO=y CLOUDCHECK=y NATNL_AICLOUD=y REBOOT_SCHEDULE=y MULTICASTIPTV=y QUAGGA=y WLCLMLOAD=n BCM_MUMIMO=y LAN50="all" ATCOVER=y GETREALIP=y CFEZ=y ETLAN_LED=y TFAT=y NTFS="tuxera" HFS="tuxera" NEWSSID_REV2=y NEWSSID_REV4=y NEW_APP_ARM=y VISUALIZATION=n BONDING=n BONDING_WAN=n NETOOL=y TRACEROUTE=y FORCE_AUTO_UPGRADE=n ALEXA=y IFTTT=y SW_HW_AUTH=y HD_SPINDOWN=y ASPMD=n BCM_MEVENT=n BCMEVENTD=n BCM_APPEVENTD=n LETSENCRYPT=y VPN_FUSION=y JFFS_NVRAM=y NVRAM_ENCRYPT=y IPSEC=STRONGSWAN IPSEC_SRVCLI_ONLY=SRV NATNL_AIHOME=y BCM_CEVENTD=y UTF8_SSID=y AMAS=y DWB=y DBLOG=y ETHOBD=y CONNDIAG=y NFCM=n CRASHLOG=y WATCH_REINIT=n BW160M=n BRCM_HOSTAPD=y UUPLUGIN=n IPERF3=y BCN_RPT=y BTM_11V=y INFO_EXAP=y FRS_LIVE_UPDATE=y AVBLCHAN=y SW_CTRL_ALLLED=y INSTANT_GUARD=y ACL96=y IPV6S46=y OCNVC=y GOOGLE_ASST=y ASUSCTRL=y WIREGUARD=y CALC_NVRAM=n COMFW=y
export RT-AX56U += AHS=n ASD=y SWRT_UU=y SWRT_FULLCONE=n SWRT_FASTPATH=y SWRT_VER_MAJOR="R" SWRT_VER_MINOR="5.2.9" SWRT_NAME="RTAX56U"
SWRT_EOF
  echo "✅ 注入完成"
fi

# rt-% 规则会 cp -ar router-sysdep.$(lowercase_B)/ router-sysdep；
# XD4 与 RT-AX56U 同平台 (BCM6755/947622GW)，复用 rt-ax56u 的 sysdep。
RSDIR="release/src-rt-5.02axhnd.675x"
if [ ! -d "$RSDIR/router-sysdep.rt-ax56_xd4" ]; then
  cp -ar "$RSDIR/router-sysdep.rt-ax56u" "$RSDIR/router-sysdep.rt-ax56_xd4"
  echo "✅ 已创建 router-sysdep.rt-ax56_xd4 (复制自 rt-ax56u)"
fi

# hostTools prebuilt: build_imageutil 依赖 prebuilt/<BUILD_NAME>/addvtoken
# （675x 树没有 addvtoken.c 源文件，只有各机型的 prebuilt 二进制；XD4 复用 RT-AX56U 的）
if [ ! -e "$RSDIR/hostTools/prebuilt/RT-AX56_XD4/addvtoken" ]; then
  mkdir -p "$RSDIR/hostTools/prebuilt/RT-AX56_XD4"
  cp -ar "$RSDIR/hostTools/prebuilt/RT-AX56U/addvtoken" "$RSDIR/hostTools/prebuilt/RT-AX56_XD4/addvtoken"
  echo "✅ 已复制 prebuilt/RT-AX56_XD4/addvtoken (来自 RT-AX56U)"
fi

# shared/prebuild/ 根下的散文件：Makefile 直接引用 prebuild/amas_wgn_shared.o
# （wildcard amas_wgn_shared.c 失败时）；386 分支只有 RT-AX55 的 prebuild 含该文件
if [ ! -e "release/src/router/shared/prebuild/amas_wgn_shared.o" ]; then
  SRC_O=$(find release/src/router/shared/prebuild -name amas_wgn_shared.o 2>/dev/null | head -1)
  if [ -n "$SRC_O" ]; then
    cp -ar "$SRC_O" release/src/router/shared/prebuild/amas_wgn_shared.o
    echo "✅ 已复制 shared/prebuild/amas_wgn_shared.o (来自 $SRC_O)"
  else
    echo "::warning::未找到 amas_wgn_shared.o 来源（RT-AX55 prebuild 缺失？）"
  fi
fi

# 通用: 为 RT-AX56_XD4 补齐所有按机型的 prebuild/prebuilt 目录（如
# protect_srv/lib/prebuild、bwdpi_source/prebuild 等私有预编译库；
# 以及 libbcm/prebuilt、libdisk/prebuilt 等预编译 .so 目录）。
# 上游源码树存在 prebuild(d) 与 prebuilt(t) 两种命名，必须同时匹配：
# 仅匹配 prebuild 时 libbcm/prebuilt/RT-AX56_XD4 不会被创建，导致
# libbcm Makefile 'cp -f ./prebuilt/RT-AX56_XD4/libbcm.so' 失败 (Error 1)。
# XD4 与 RT-AX56U 同平台 BCM6755，产物兼容。
while IFS= read -r d; do
  if [ -d "$d/RT-AX56U" ] && [ ! -e "$d/RT-AX56_XD4" ]; then
    cp -ar "$d/RT-AX56U" "$d/RT-AX56_XD4"
    echo "✅ prebuild 补齐: $d/RT-AX56U → RT-AX56_XD4"
  fi
done < <(find release/src/router -maxdepth 4 -type d \( -name prebuild -o -name prebuilt \) 2>/dev/null)

# 双保险: amas_wgn_shared.o 也放进 RT-AX56_XD4 镜像目录
# （RT-AX56U 的 shared prebuild 缺该文件，从 RT-AX55 补；防止 make 解析路径差异）
if [ -e "release/src/router/shared/prebuild/RT-AX55/amas_wgn_shared.o" ] && [ ! -e "release/src/router/shared/prebuild/RT-AX56_XD4/amas_wgn_shared.o" ]; then
  cp -ar "release/src/router/shared/prebuild/RT-AX55/amas_wgn_shared.o" "release/src/router/shared/prebuild/RT-AX56_XD4/amas_wgn_shared.o"
  echo "✅ 双保险: RT-AX56_XD4/amas_wgn_shared.o 已补齐"
fi

# shared/prebuild/ 根下散文件补齐: Makefile 的 private.o/nvpriv.o 规则直接检查
# ./prebuild/XXX.o (根 prebuild, 非机型子目录)。386 分支 prebuild 根目录只有机型
# 子目录无散文件, 导致 private.o: 规则的 ifneq($(wildcard ./prebuild/private.o))
# 为假 -> recipe 为空 -> make 回退到 %.o: %.c -> private.c 不存在 ->
# "No rule to make target 'private.c', needed by 'private.o'"
# 同理 nvpriv.o (JFFS_NVRAM=y)、bcmutils.o/bcmwifi_channels.o/bcmxtlv.o 等。
# 修复: 将 RT-AX56_XD4 机型 prebuild 下的所有 .o 复制到根 prebuild (同平台 BCM6755,
# 产物兼容; 仅在根不存在时复制, 不覆盖已有文件如 amas_wgn_shared.o)
PREBUILD_ROOT="release/src/router/shared/prebuild"
if [ -d "$PREBUILD_ROOT/RT-AX56_XD4" ]; then
  for o in "$PREBUILD_ROOT/RT-AX56_XD4"/*.o; do
    [ -f "$o" ] || continue
    base=$(basename "$o")
    if [ ! -e "$PREBUILD_ROOT/$base" ]; then
      cp -ar "$o" "$PREBUILD_ROOT/$base"
      echo "✅ 已复制 shared/prebuild/$base (来自 RT-AX56_XD4)"
    fi
  done
else
  echo "::warning::prebuild/RT-AX56_XD4 不存在, 无法补齐根 prebuild 散文件"
fi

# rc/prebuild SOFTWIRE46 对象补齐: XD4 启用 IPV6S46=y (-> RTCONFIG_SOFTWIRE46)，
# rc/Makefile 在该条件下把 s46comm.o (OBJS line 323) 与 v6plusd.o/ocnvcd.o/dslited.o
# (OBJS line 712) 加入 rc 链接，并通过 ./prebuild/<name>.o (根目录) 的 wildcard 规则
# 从 prebuild 拷贝。但 RT-AX56U 的 rc/prebuild 缺这 4 个文件 (只有 Makefile 未引用的
# s46map_rptd.o)；RT-AX55 (同平台 947622GW/675x，$(HND-947622_BASE_NOUSB)) 的
# rc/prebuild 含全部 4 个 -> 从 RT-AX55 补齐。
# 修复: "No rule to make target 's46comm.o', needed by 'rc'" 及后续 v6plusd/ocnvc/dslite。
# gpy211_war.o: XD4 启用 HND_ROUTER_AX_675X=y (-> RTCONFIG_HND_ROUTER_AX)，rc/Makefile
# (OBJS line 799) 把它加入 rc 链接，同样依赖 ./prebuild/gpy211_war.o 的 wildcard 规则；
# RT-AX56U 的 rc/prebuild 缺该文件，RT-AX55 (同平台 947622GW/675x) 含 -> 一并从 RT-AX55 补齐。
# 修复: "No rule to make target 'gpy211_war.o', needed by 'rc'"。
# 双保险: 同时放入 RT-AX56_XD4 机型目录 (构建系统按 BUILD_NAME staging) 与根 prebuild
# (Makefile wildcard ./prebuild/<name>.o 直接命中)，与 amas_wgn_shared.o 处理方式一致。
RC_PREBUILD="release/src/router/rc/prebuild"
for s46obj in s46comm.o v6plusd.o ocnvcd.o dslited.o gpy211_war.o; do
  SRC_O=$(find "$RC_PREBUILD" -name "$s46obj" 2>/dev/null | head -1)
  if [ -n "$SRC_O" ]; then
    # 机型目录 (构建系统按 BUILD_NAME 拷贝 prebuild 子目录到根)
    if [ ! -e "$RC_PREBUILD/RT-AX56_XD4/$s46obj" ]; then
      cp -ar "$SRC_O" "$RC_PREBUILD/RT-AX56_XD4/$s46obj"
      echo "✅ 已复制 rc/prebuild/RT-AX56_XD4/$s46obj (来自 $(basename "$(dirname "$SRC_O")"))"
    fi
    # 根 prebuild (Makefile wildcard ./prebuild/<name>.o 直接命中)
    if [ ! -e "$RC_PREBUILD/$s46obj" ]; then
      cp -ar "$SRC_O" "$RC_PREBUILD/$s46obj"
      echo "✅ 已复制 rc/prebuild/$s46obj (双保险, 来自 $(basename "$(dirname "$SRC_O")"))"
    fi
  else
    echo "::warning::未找到 rc/prebuild/$s46obj (RT-AX55 prebuild 缺失？)"
  fi
done

# rc/prebuild amas_wgn.o 补齐: XD4 启用 AMAS_WGN=y (-> RTCONFIG_AMAS_WGN)，
# rc/Makefile 在该条件下把 amas_wgn.o 加入 rc 链接，并通过 ./prebuild/<name>.o
# (根目录) 的 wildcard 规则从 prebuild 拷贝。但 RT-AX56U 的 rc/prebuild 缺该文件
# (RT-AX56U 定义无 AMAS_WGN)；RT-AX55 (同平台 947622GW/675x) 的 rc/prebuild 含
# amas_wgn.o (RT-AX55 启用 AMAS_WGN，其 shared/prebuild 已含 amas_wgn_shared.o)。
# 修复: "No rule to make target 'amas_wgn.o', needed by 'rc'"。
# 双保险: 同时放入 RT-AX56_XD4 机型目录与根 prebuild，与 s46comm.o 处理方式一致。
for amasobj in amas_wgn.o; do
  SRC_O=$(find "$RC_PREBUILD" -name "$amasobj" 2>/dev/null | head -1)
  if [ -n "$SRC_O" ]; then
    # 机型目录 (构建系统按 BUILD_NAME 拷贝 prebuild 子目录到根)
    if [ ! -e "$RC_PREBUILD/RT-AX56_XD4/$amasobj" ]; then
      cp -ar "$SRC_O" "$RC_PREBUILD/RT-AX56_XD4/$amasobj"
      echo "✅ 已复制 rc/prebuild/RT-AX56_XD4/$amasobj (来自 $(basename "$(dirname "$SRC_O")"))"
    fi
    # 根 prebuild (Makefile wildcard ./prebuild/<name>.o 直接命中)
    if [ ! -e "$RC_PREBUILD/$amasobj" ]; then
      cp -ar "$SRC_O" "$RC_PREBUILD/$amasobj"
      echo "✅ 已复制 rc/prebuild/$amasobj (双保险, 来自 $(basename "$(dirname "$SRC_O")"))"
    fi
  else
    echo "::warning::未找到 rc/prebuild/$amasobj (所有机型 prebuild 缺失？)"
  fi
done

# udev-173/bluez-5.56: 老 config.sub 不认识 autoconf 2.71 的 --force 参数
# （XD4 是 386 分支首个启用 bluez 依赖链的机型，官方 CI 从未构建过；
#   注：BT_CONN 已从 XD4 定义移除——386 分支没有 bleencrypt/gatt-amap.h，
#   保留 BT_CONN=y 会触发 --enable-extaqis 编译 aqis 时找不到头文件；
#   udev configure 失败 → libudev.so 缺失 → bluez conftest 链接失败）
# 方案: 预生成 configure（make 的 autoreconf 步骤因目标已存在而跳过）+
# 用 gcc-mirror 最新 config.sub/config.guess 替换（支持 --force）
fetch_config_sub() {
  local dir="$1"
  mkdir -p "$dir/build-aux"
  if curl -fsSL --retry 3 --connect-timeout 20 -o "$dir/build-aux/config.sub" \
      https://raw.githubusercontent.com/gcc-mirror/gcc/master/config.sub 2>/dev/null; then
    curl -fsSL --retry 3 --connect-timeout 20 -o "$dir/build-aux/config.guess" \
        https://raw.githubusercontent.com/gcc-mirror/gcc/master/config.guess 2>/dev/null || true
    chmod +x "$dir/build-aux/config.sub" "$dir/build-aux/config.guess" 2>/dev/null || true
    # 老式 autoconf 包 (udev-173 等) 不设 AC_CONFIG_AUX_DIR([build-aux])，
    # configure 在根目录查找 config.sub；仅放 build-aux/ 会导致 configure
    # 用旧 config.sub -> configure: exit 1 -> libudev.so 缺失 -> rc 链接失败。
    cp -f "$dir/build-aux/config.sub" "$dir/config.sub" 2>/dev/null || true
    cp -f "$dir/build-aux/config.guess" "$dir/config.guess" 2>/dev/null || true
    echo "✅ $dir: config.sub/config.guess 已更新 (gcc-mirror, build-aux + root)"
    return 0
  fi
  echo "::warning::$dir: config.sub 下载失败"
  return 1
}
# 预生成 configure（与 router/Makefile 相同的命令），使 make 跳过 autoreconf 覆盖
(cd release/src/router/udev-173 && ./autogen.sh --host --force >/dev/null 2>&1; autoreconf --force --install >/dev/null 2>&1) || true
(cd release/src/router/bluez-5.56 && ./autogen.sh --no-configure >/dev/null 2>&1) || true
fetch_config_sub release/src/router/udev-173 || true
fetch_config_sub release/src/router/bluez-5.56 || true

# bluez 链接 libshared.so 时的未定义符号修复：
# hnd_boardid_cmp / check_mssid_prelink_reset 在 386 分支整个源码树中只有声明和调用
# （上游缺陷：RT-AX55 无 MSSID_PRELINK、无 BT_CONN（XD4 定义已移除 BT_CONN 与
#   MSSID_PRELINK——386 分支 675x 平台无 amas_prelink.o 预编译产物，PRELINK=y
#   会导致 rc 链接失败 "No rule to make target 'amas_prelink.o'"）。
# 在 shared/misc.c 末尾注入最小定义（stub 语义：boardid 比较用 nvram，prelink 重置为空操作）。
SHARED_MISC="release/src/router/shared/misc.c"
if ! grep -q "hnd_boardid_cmp(const char \*id)" "$SHARED_MISC"; then
  cat >> "$SHARED_MISC" <<'STUB_EOF'

/* === AutoBuild_Merlin_for_ZenWiFi_XD4 注入: 386 分支缺失的符号定义 === */
/* hnd_boardid_cmp: HND 板 ID 比较（HND 驱动板 ID 在用户态不可直接获取，
 * 用 nvram boardid 近似；XD4 上 model.c 只对 RT-BE96U 等分支调用，影响面小） */
int hnd_boardid_cmp(const char *id)
{
	const char *bid = nvram_safe_get("boardid");
	if (bid == NULL || *bid == '\0')
		return -1;
	return strcmp(bid, id);
}

/* check_mssid_prelink_reset: MSSID_PRELINK 重置检查（386 分支源码缺失定义，
 * 上游仅在 master/24353 的预编译产物中存在；空实现 = 不执行 prelink 重置） */
void check_mssid_prelink_reset(uint32_t sf)
{
	(void)sf;
}
STUB_EOF
  echo "✅ 已注入 hnd_boardid_cmp/check_mssid_prelink_reset stub 到 shared/misc.c"
fi
find release/src/router -maxdepth 4 -type d \( -name prebuild -o -name prebuilt \) -exec test -d '{}/RT-AX56_XD4' \; -print 2>/dev/null | head -5 | xargs -I{} echo "  prebuild 存在: {}" || true

echo "=== 验证 ==="
grep -c "RT-AX56_XD4" "$TARGET_MAK" | xargs echo "RT-AX56_XD4 出现次数:"
ls -d "$RSDIR/router-sysdep.rt-ax56_xd4" >/dev/null && echo "router-sysdep.rt-ax56_xd4: OK"
ls "$RSDIR/hostTools/prebuilt/RT-AX56_XD4/addvtoken" >/dev/null && echo "prebuilt/RT-AX56_XD4/addvtoken: OK"
