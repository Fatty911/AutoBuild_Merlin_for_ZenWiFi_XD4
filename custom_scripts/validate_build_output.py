#!/usr/bin/env python3
"""ZenWiFi XD4 Merlin 固件构建质量门。

检查:
1. 固件文件存在且文件名匹配预期机型模式 (RT-AX56_XD4_*.trx)
2. 固件大小 >= 最小阈值
3. 软件中心 (softcenter) 已集成在源码中

用法:
    validate_build_output.py --gate          # 质量门模式（硬失败）
    validate_build_output.py                 # 报告模式（只输出信息）
"""

import argparse
import glob
import os
import sys
from pathlib import Path

WORKSPACE = Path(os.environ.get("GITHUB_WORKSPACE", "."))
SDK_DIR = os.environ.get("SDK_DIR", "src-rt-5.02axhnd.675x")
SOURCE_DIR = WORKSPACE / "asuswrt-bcm"


def find_firmware(expected_pattern: str, minimum_size_mb: float) -> list[Path]:
    image_dir = SOURCE_DIR / "release" / SDK_DIR / "image"
    if not image_dir.is_dir():
        print(f"❌ 输出目录不存在: {image_dir}")
        return []
    all_trx = sorted(image_dir.glob("*.trx"))
    print(f"输出目录: {image_dir}")
    print(f"找到 .trx 文件: {len(all_trx)}")
    for p in all_trx:
        print(f"  - {p.name} ({p.stat().st_size / 1024 / 1024:.2f} MB)")
    matched = [p for p in all_trx if expected_pattern.lower() in p.name.lower()]
    if not matched and all_trx:
        print(f"⚠️ 没有文件名包含机型模式 '{expected_pattern}' 的固件")
    return matched


def check_softcenter() -> bool:
    sc = SOURCE_DIR / "release" / "src" / "router" / "softcenter"
    ok = (sc / "Softcenter.asp").is_file() and (sc / "softcenter" / "bin" / "softcenter.sh").is_file()
    print(f"软件中心集成: {'✅ 已确认' if ok else '❌ 缺失'} ({sc})")
    return ok


def check_firmware_size(fw: Path, minimum_size_mb: float) -> bool:
    size_mb = fw.stat().st_size / (1024 * 1024)
    ok = size_mb >= minimum_size_mb
    print(f"固件大小: {size_mb:.2f} MB (要求 >= {minimum_size_mb} MB) {'✅' if ok else '❌'}")
    return ok


def main() -> int:
    parser = argparse.ArgumentParser(description="Merlin 固件构建质量门")
    parser.add_argument("--gate", action="store_true", help="质量门模式: 不通过则退出码 1")
    args = parser.parse_args()

    expected_pattern = os.environ.get("EXPECTED_MODEL_PATTERN", "RT-AX56_XD4")
    min_size_mb = float(os.environ.get("MIN_FIRMWARE_SIZE_MB", "10"))

    print("=" * 60)
    print(f"构建质量门 | 机型模式: {expected_pattern} | 最小大小: {min_size_mb} MB")
    print("=" * 60)

    fw_files = find_firmware(expected_pattern, min_size_mb)
    softcenter_ok = check_softcenter()

    passed = softcenter_ok and bool(fw_files)
    for fw in fw_files:
        if not check_firmware_size(fw, min_size_mb):
            passed = False

    print("=" * 60)
    if passed:
        print("✅ 质量门通过: 固件存在、大小达标、软件中心已集成")
        if args.gate:
            print("gate_result=pass")
        return 0
    print("❌ 质量门未通过: 固件不可发布")
    if args.gate:
        print("gate_result=fail")
    return 1


if __name__ == "__main__":
    sys.exit(main())
