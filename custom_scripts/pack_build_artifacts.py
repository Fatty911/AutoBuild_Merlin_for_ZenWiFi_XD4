#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Merlin 编译产物打包/恢复（增量构建专用）。

只打包对象/库产物（.o/.a/.so/.lo/.ko），排除源码与上游预编译目录——
之前 Save phase1 保存整个 release（源码+产物 ~10GB）导致 GitHub cache
超限静默失败，增量恢复从未生效（每次全量编译 ~50 分钟）。

用法：
  pack_build_artifacts.py pack <release_dir> <out.tar.zst>
  pack_build_artifacts.py unpack <release_dir> <in.tar.zst>

压缩器优先级：zstd → pigz → gzip（全部缺失时退化为不压缩 tar）。
"""

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

EXTENSIONS = (".o", ".a", ".so", ".lo", ".ko")
# 只排除明确目录：prebuild/prebuilt 是上游预编译（源码树已有，无需打包）；
# .git/dl/image/targets 非产物。注意不能排除所有点目录——libtool 构建的
# .libs/ 子目录存放库产物（.o/.a/.so），漏打包会导致增量恢复链接失败
EXCLUDE_DIRS = {"prebuild", "prebuilt", ".git", "dl", "image", "targets"}


def pick_compressor():
    for prog, args in (("zstd", None), ("pigz", None), ("gzip", None)):
        if shutil.which(prog):
            return prog
    return None


def collect_files(release_dir):
    files = []
    for root, dirs, fnames in os.walk(release_dir):
        # 例外：hnd_extra/prebuilt 是构建生成物（busybox 构建链生成，上游
        # git 没有），必须打包——否则增量恢复后 busybox 重编缺 detect_opt.o
        dirs[:] = [
            d for d in dirs
            if d not in EXCLUDE_DIRS
            or (d == "prebuilt" and "hnd_extra" in Path(root).parts)
        ]
        for fn in fnames:
            if fn.endswith(EXTENSIONS):
                files.append(Path(root) / fn)
    return files


def cmd_pack(args):
    release_dir = Path(args.release_dir)
    if not release_dir.is_dir():
        print(f"::error::release 目录不存在: {release_dir}")
        return 1
    files = collect_files(release_dir)
    if not files:
        print("ℹ️ 无产物可打包（全量编译未开始或全部失败）")
        return 0
    # 用 manifest 传文件列表（避免命令行超长）
    manifest = release_dir / ".phase1-manifest.txt"
    manifest.write_text(
        "\n".join(str(f.relative_to(release_dir)) for f in files),
        encoding="utf-8",
    )
    out = Path(args.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    compressor = pick_compressor()
    cmd = ["tar", "cf", str(out)]
    if compressor:
        cmd += ["--use-compress-program", compressor]
    # 注意: -C 必须在 -T 之前（-T 文件列表中的相对路径按 -C 目录解析）
    cmd += ["-C", str(release_dir), "-T", str(manifest)]
    result = subprocess.run(cmd, capture_output=True, text=True)
    manifest.unlink(missing_ok=True)
    if result.returncode != 0 or not out.exists():
        print(f"::error::打包失败: {result.stderr[-300:]}")
        return 1
    size_mb = out.stat().st_size / 1024 / 1024
    print(f"✅ phase1 产物打包: {len(files)} 个文件, {size_mb:.1f} MB → {out}")
    return 0


def prune_half_dirs(release_dir):
    """清理 tar 解压型组件的半成品顶层目录。

    根因（2026-08-10 增量恢复实测）：老式 Makefile 用
    `if [ ! -e <dir> ]; then tar x ...; fi` 判断是否解压源码包——
    产物目录被恢复后目录存在 → 跳过解压 → configure/Makefile 缺失 →
    `./configure: No such file or directory`（Error 127，config_xz-5.0.3 实例）。

    只处理"父目录存在对应源码包（*.tar.*）"的顶层目录：删除后 make 的
    tar 分支必然重新解压完整源码，绝对安全。不处理深层目录（make 不做
    目录存在性检查）与 prebuild/prebuilt（git 自带，非 tar 解压）。
    """
    ART_EXT = (".o", ".a", ".so", ".lo", ".ko")
    TAR_EXT = (".tar.gz", ".tar.bz2", ".tar.xz", ".tgz", ".tbz2", ".tar")
    GEN_MARKERS = ("Makefile", "configure", "config.status", "config.log")
    pruned = 0
    for root, dirs, files in os.walk(release_dir, topdown=False):
        # 路径任意组件以 prebuild/prebuilt 开头都保护（目录名带后缀，
        # 如 prebuilt.hnd_ax / prebuild.RT-AX56U——git 自带，非 tar 解压）
        if any(p.startswith(("prebuild", "prebuilt")) for p in Path(root).parts):
            continue
        parent = Path(root).parent
        try:
            parent_files = os.listdir(parent)
        except OSError:
            continue
        if not any(f.endswith(TAR_EXT) for f in parent_files):
            continue  # 非 tar 解压型组件，交给 make 自身逻辑
        has_art = any(f.endswith(ART_EXT) for f in files)
        # 精确名匹配：Makefile.am/Makefile.in 是源码自带（autoconf 输入），
        # 只有生成的 Makefile/configure/config.status 才算"完整构建过"
        has_gen = any(f in GEN_MARKERS for f in files)
        if has_art and not has_gen:
            # 找到匹配的源码包（如 xz-5.0.3 → xz-5.0.3.tar.bz2）
            pkg = next(
                (f for f in parent_files
                 if f.endswith(TAR_EXT) and f.startswith(Path(root).name + ".")),
                None,
            )
            shutil.rmtree(root, ignore_errors=True)
            pruned += 1
            if pkg:
                # 立即重新解压补全（不等 make：其 tar 分支有 || true 吞错风险，
                # 且源码树自带目录时 make 会跳过解压直接失败）
                r = subprocess.run(
                    ["tar", "xf", str(parent / pkg), "-C", str(parent)],
                    capture_output=True, text=True,
                )
                print(f"🧹 清理半成品目录: {root} → 已重新解压 {pkg}"
                      + ("" if r.returncode == 0 else f"（解压失败: {r.stderr[-120:]}）"))
            else:
                print(f"🧹 清理半成品目录: {root}")
    return pruned


def cmd_unpack(args):
    release_dir = Path(args.release_dir)
    archive = Path(args.input)
    if not archive.is_file():
        print(f"::error::产物包不存在: {archive}")
        return 1
    release_dir.mkdir(parents=True, exist_ok=True)
    compressor = pick_compressor()
    cmd = ["tar", "xf", str(archive)]
    if compressor:
        cmd += ["--use-compress-program", compressor]
    cmd += ["-C", str(release_dir)]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"::warning::产物解压失败（将全量编译）: {result.stderr[-200:]}")
        return 1
    print(f"✅ phase1 产物已恢复: {archive} → {release_dir}")
    pruned = prune_half_dirs(release_dir)
    if pruned:
        print(f"✅ 半成品目录清理完成（{pruned} 个，make 将重新解压源码）")
    return 0


def main():
    parser = argparse.ArgumentParser(description="Merlin 编译产物打包/恢复")
    sub = parser.add_subparsers(dest="mode", required=True)
    p_pack = sub.add_parser("pack")
    p_pack.add_argument("release_dir")
    p_pack.add_argument("output")
    p_pack.set_defaults(func=cmd_pack)
    p_unpack = sub.add_parser("unpack")
    p_unpack.add_argument("release_dir")
    p_unpack.add_argument("input")
    p_unpack.set_defaults(func=cmd_unpack)
    args = parser.parse_args()
    sys.exit(args.func(args))


if __name__ == "__main__":
    main()
