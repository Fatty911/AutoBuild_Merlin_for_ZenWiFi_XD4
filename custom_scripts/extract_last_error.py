#!/usr/bin/env python3
"""从构建日志中提取最后的错误块，便于 AI 修复和人工排查。

用法:
    extract_last_error.py --log build.log --output last_error.log
"""

import argparse
import re
import sys
from pathlib import Path

ERROR_PATTERNS = [
    re.compile(r"make.*\*\*\*.*Error", re.IGNORECASE),
    re.compile(r"\*\*\*.*(?:No rule to make target|recipe for target).*failed"),
    re.compile(r"(?:fatal error|undefined reference|No such file|command not found)",
               re.IGNORECASE),
    re.compile(r"make\[\d+\]: \*\*\*"),
    re.compile(r"configure: error"),
    re.compile(r"cc1?:?\s*(?:error|fatal)"),
    re.compile(r"collect2: error"),
]


def find_failed_component(lines):
    """从 build.log 中定位失败组件：最后一个进入的 release/src/router/<组件> 目录。

    梅林 make 输出 'make[N]: Entering directory '.../release/src/router/<comp>''，
    失败组件的标志是：进入后出现了 error/failed 行。若无法定位返回 None。
    同时返回该组件之前的所有成功组件（phase1 列表）。
    """
    comp_re = re.compile(r"Entering directory.*?/release/src/router/([^/'\"']+)")
    needed_re = re.compile(r"needed by '([^']+)'")
    makefile_re = re.compile(r"\[Makefile:\d+: ([A-Za-z0-9_]+)\] Error")
    visited = []          # 进入顺序
    last_dir = None
    last_dir_idx = -1
    failed = None
    for i, line in enumerate(lines):
        m = comp_re.search(line)
        if m:
            comp = m.group(1)
            if comp not in visited:
                visited.append(comp)
            last_dir = comp
            last_dir_idx = i
        elif last_dir and (last_dir_idx >= 0) and (i - last_dir_idx <= 5000):
            if "warning" in line.lower():
                continue  # cc1: warning 常含 "No such file"（-I 目录缺失），非错误
            if "ignored" in line.lower():
                continue  # make 的 "Error 1 (ignored)" 是被 - 前缀忽略的失败，非真失败
            # 优先从错误行直接提取组件名："No rule to make target 'xxx.o', needed
            # by 'rc'" → rc；"[Makefile:3256: rc] Error 2" → rc。比目录跟踪更可靠
            # （rc 并行编译时 Entering directory 与最终错误可能间隔上千行）。
            nm = needed_re.search(line)
            if nm and nm.group(1) in visited:
                failed = nm.group(1)
                continue
            mm = makefile_re.search(line)
            if mm and mm.group(1) in visited:
                failed = mm.group(1)
                continue
            if any(p.search(line) for p in ERROR_PATTERNS):
                # 不立即 break：日志可能先出现 ignored/早期错误，取最后一个真错误
                # 对应的组件（首个匹配可能是 shared 等组件的非致命错误）
                failed = last_dir
    if failed and failed in visited:
        phase1 = visited[: visited.index(failed)]
    else:
        phase1 = visited[:-1] if visited else []
    return failed, phase1, last_dir


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--log", required=True)
    parser.add_argument("--output", default="last_error.log")
    parser.add_argument("--max-chars", type=int, default=8000)
    args = parser.parse_args()

    log_path = Path(args.log)
    if not log_path.is_file():
        print(f"❌ 日志不存在: {log_path}")
        return 1

    lines = log_path.read_text(errors="replace").splitlines()
    total = len(lines)
    if total == 0:
        print("❌ 日志为空")
        return 1

    # 找到最后一个错误行的位置
    last_err_idx = -1
    for i, line in enumerate(lines):
        if any(p.search(line) for p in ERROR_PATTERNS):
            last_err_idx = i

    if last_err_idx < 0:
        # 没有匹配到错误模式，取最后 100 行
        start = max(0, total - 100)
        context = lines[start:]
    else:
        start = max(0, last_err_idx - 30)
        context = lines[start : min(total, last_err_idx + 80)]

    text = "\n".join(context)
    if len(text) > args.max_chars:
        text = text[-args.max_chars:]

    # 失败组件定位（phase1/phase2 增量修复用）
    failed_comp, phase1_list, last_dir = find_failed_component(lines)
    if failed_comp:
        header = f"### 失败组件: {failed_comp} ###\n"
        header += f"### PHASE1: {','.join(phase1_list) if phase1_list else '(无)'} ###\n"
        text = header + text
        print(f"🔧 失败组件: {failed_comp} (phase1={len(phase1_list)} 个组件已成功)")
    elif last_dir:
        print(f"ℹ️ 最后进入组件目录: {last_dir}（未捕获错误行，按保守处理）")

    Path(args.output).write_text(text, encoding="utf-8")
    print(f"✅ 已提取错误日志: {args.output} ({len(text)} chars, 行 {start}-{start + len(context)})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
