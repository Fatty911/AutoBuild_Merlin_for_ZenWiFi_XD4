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
export HND-947622_BASE := HND_ROUTER=y HND_ROUTER_AX_675X=y PROFILE="947622GW" SAMBA3="3.6.x" OOKLA=y WL_SCHED_V3=y CABLEDIAG=y SOFTCENTER=y UBI=y UBIFS=y PSISTLOG=y SMARTDNS=y CIFS=y SWRT=y ENTWARE=y CAPTCHA=y
export HND-947622_BASE_NOUSB := HND_ROUTER=y HND_ROUTER_AX_675X=y PROFILE="947622GW" WL_SCHED_V3=y OOKLA=y CABLEDIAG=y SOFTCENTER=y UBI=y UBIFS=y PSISTLOG=y SMARTDNS=y CIFS=y SWRT=y CAPTCHA=y
export RT-AX56_XD4 := $(HND-947622_BASE_NOUSB)
export RT-AX56_XD4 += BUILD_NAME="RT-AX56_XD4" NVSIZE="128" DHDAP=y HND_WL=y DPSTA=y LACP=n WTFAST=n REPEATER=y DISABLE_REPEATER_UI=y DISABLE_PROXYSTA_UI=y IPV6SUPP=y HTTPS=y ARM=y AUTODICT=y BBEXTRAS=y USBEXTRAS=y EBTABLES=y MEDIASRV=n MODEM=n PARENTAL2=y ACCEL_PPTPD=y PRINTER=n WEBDAV=n SMARTSYNCBASE=n USB="USB" APP="none" PROXYSTA=y DNSMQ=y SHP=n BCMWL6=y BCMWL6A=y DISK_MONITOR=n BTN_WIFITOG=n OPTIMIZE_XBOX=y ODMPID=y LED_BTN=n BCMSMP=y XHCI=n DUALWAN=n  NEW_USER_LOW_RSSI=y OPENVPN=y TIMEMACHINE=n MDNS=y VPNC=y BRCM_NAND_JFFS2=y JFFS2LOG=y BWDPI=y DUMP_OOPS_MSG=n LINUX_MTD="64" DEBUGFS=y TEMPROOTFS=n SSH=y EMAIL=y FRS_FEEDBACK=y SYSSTATE=y ROG=n STAINFO=y CLOUDCHECK=n NATNL_AICLOUD=n REBOOT_SCHEDULE=y MULTICASTIPTV=y QUAGGA=y WLCLMLOAD=n BCM_MUMIMO=y LAN50="all" ATCOVER=y GETREALIP=y CFEZ=y ETLAN_LED=n TFAT=n NTFS="" HFS="" NEWSSID_REV2=y NEWSSID_REV4=y NEWSSID_REV5=y NEW_APP_ARM=y VISUALIZATION=n BONDING=n BONDING_WAN=n NETOOL=y TRACEROUTE=y FORCE_AUTO_UPGRADE=y ALEXA=y IFTTT=y SW_HW_AUTH=y ASPMD=n BCM_MEVENT=n BCM_APPEVENTD=n LETSENCRYPT=y VPN_FUSION=y JFFS_NVRAM=y NVRAM_ENCRYPT=y IPSEC=STRONGSWAN IPSEC_SRVCLI_ONLY=SRV NATNL_AIHOME=n BCM_CEVENTD=y UTF8_SSID=y AMAS=y DWB=y DBLOG=y ETHOBD=y CONNDIAG=y NFCM=n CRASHLOG=y WATCH_REINIT=y BW160M=n BRCM_HOSTAPD=y TCPLUGIN=y UUPLUGIN=y IPERF3=y INFO_EXAP=y FRS_LIVE_UPDATE=y AVBLCHAN=y NO_SAMBA=y NO_FTP=y NO_USBSTORAGE=y BT_CONN=y BCM_CLED=y SINGLE_LED=y BHCOST_OPT=y AMAS_WGN=y MSSID_PRELINK=y AMAZON_WSS=y AHS=y ASD=y INTERNETCTRL=y SW_CTRL_ALLLED=y HSPOT=y BCN_RPT=y BTM_11V=y BCMEVENTD=y PORT2_DEVICE=y URLFW=y AMAS_SYNC_2G_BW=y INSTANT_GUARD=y AMAS_ETHDETECT=y ACL96=y IPV6S46=y OCNVC=y GOOGLE_ASST=y ASUSCTRL=y WIREGUARD=y CALC_NVRAM=y COMFW=y SWRT_VER_MAJOR="R" SWRT_VER_MINOR="5.2.9" SWRT_NAME="RTAX56XD4"
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

# 通用: 为 RT-AX56_XD4 补齐所有按机型的 prebuild 目录（如 protect_srv/lib/prebuild、
# bwdpi_source/prebuild 等私有预编译库；XD4 与 RT-AX56U 同平台 BCM6755，产物兼容）
while IFS= read -r d; do
  if [ -d "$d/RT-AX56U" ] && [ ! -e "$d/RT-AX56_XD4" ]; then
    cp -ar "$d/RT-AX56U" "$d/RT-AX56_XD4"
    echo "✅ prebuild 补齐: $d/RT-AX56U → RT-AX56_XD4"
  fi
done < <(find release/src/router -maxdepth 4 -type d -name prebuild 2>/dev/null)

# 双保险: amas_wgn_shared.o 也放进 RT-AX56_XD4 镜像目录
# （RT-AX56U 的 shared prebuild 缺该文件，从 RT-AX55 补；防止 make 解析路径差异）
if [ -e "release/src/router/shared/prebuild/RT-AX55/amas_wgn_shared.o" ] && [ ! -e "release/src/router/shared/prebuild/RT-AX56_XD4/amas_wgn_shared.o" ]; then
  cp -ar "release/src/router/shared/prebuild/RT-AX55/amas_wgn_shared.o" "release/src/router/shared/prebuild/RT-AX56_XD4/amas_wgn_shared.o"
  echo "✅ 双保险: RT-AX56_XD4/amas_wgn_shared.o 已补齐"
fi
find release/src/router -maxdepth 4 -type d -name prebuild -exec test -d '{}/RT-AX56_XD4' \; -print 2>/dev/null | head -5 | xargs -I{} echo "  prebuild 存在: {}" || true

echo "=== 验证 ==="
grep -c "RT-AX56_XD4" "$TARGET_MAK" | xargs echo "RT-AX56_XD4 出现次数:"
ls -d "$RSDIR/router-sysdep.rt-ax56_xd4" >/dev/null && echo "router-sysdep.rt-ax56_xd4: OK"
ls "$RSDIR/hostTools/prebuilt/RT-AX56_XD4/addvtoken" >/dev/null && echo "prebuilt/RT-AX56_XD4/addvtoken: OK"
