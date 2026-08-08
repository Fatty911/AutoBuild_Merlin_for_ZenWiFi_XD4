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
    # 现代 GCC/Clang 错误格式: file.c:line:col: error: message
    # 旧 patterns 只匹配 cc1:/collect2: 前缀的链接器错误，漏掉普通编译错误
    # (如 "rc.c:123:45: error: 'foo' undeclared")，导致 find_first_error_in_range
    # 返回 -1，"失败组件实际错误段" 缺失，last_error.log 只剩 make 错误链。
    re.compile(r":\d+:\d+:\s*(?:error|fatal error):"),
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


def find_component_range(lines, component):
    """定位组件在 build.log 中的构建输出范围 (Entering ... Leaving directory)。

    并行 make (-jN) 下，rc 等大组件的 Entering/Leaving 之间可能间隔数千行，
    实际编译/链接错误藏在其中，远早于最终的 ``make: *** Error 2`` 链。
    返回 (enter_idx, leave_idx)；找不到返回 (-1, -1)。
    """
    if not component:
        return -1, -1
    enter_re = re.compile(
        rf"Entering directory.*?/release/src/router/{re.escape(component)}['\"]"
    )
    leave_re = re.compile(
        rf"Leaving directory.*?/release/src/router/{re.escape(component)}['\"]"
    )
    # 取最后一次 Entering（组件可能被多次进入），以及其后的首次 Leaving
    enter_idx = -1
    leave_idx = -1
    for i, line in enumerate(lines):
        if enter_re.search(line):
            enter_idx = i
        if leave_re.search(line) and enter_idx >= 0:
            leave_idx = i
            break
    return enter_idx, leave_idx


def find_first_error_in_range(lines, start, end):
    """在 [start, end) 范围内查找首个真实错误行。

    跳过 warning 行（cc1 warning 常含 "No such file"，非错误）和
    ignored 行（make 的 "Error 1 (ignored)" 是被 - 前缀忽略的失败）。
    限制搜索范围防止超大日志慢扫描。
    """
    if start < 0:
        return -1
    if end < 0 or end > len(lines):
        end = len(lines)
    search_end = min(end, start + 20000)
    for i in range(start, search_end):
        line = lines[i]
        if "warning" in line.lower():
            continue
        if "ignored" in line.lower():
            continue
        if any(p.search(line) for p in ERROR_PATTERNS):
            return i
    return -1


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--log", required=True)
    parser.add_argument("--output", default="last_error.log")
    parser.add_argument("--max-chars", type=int, default=16000)
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

    failed_comp, phase1_list, last_dir = find_failed_component(lines)

    last_err_idx = -1
    for i, line in enumerate(lines):
        if any(p.search(line) for p in ERROR_PATTERNS):
            last_err_idx = i

    # 并行 make (-jN) 下，rc 等大组件的真正编译/链接错误可能比最终
    # make: *** Error 2 链早数百甚至数千行（被其它文件的输出淹没）。
    # 旧逻辑只取最后错误行前 30 行，在并行构建中几乎必定漏掉根因。
    # 修复：在失败组件的 Entering..Leaving directory 范围内搜索首个真实错误。
    first_err_idx = -1
    if failed_comp:
        enter_idx, leave_idx = find_component_range(lines, failed_comp)
        if enter_idx >= 0:
            first_err_idx = find_first_error_in_range(lines, enter_idx, leave_idx)

    sections = []  # (title, start, end)

    if first_err_idx >= 0 and (last_err_idx < 0 or first_err_idx < last_err_idx - 5):
        s = max(0, first_err_idx - 25)
        e = min(total, first_err_idx + 45)
        sections.append(("失败组件实际错误段", s, e))

    if last_err_idx >= 0:
        s = max(0, last_err_idx - 10)
        e = min(total, last_err_idx + 80)
        sections.append(("Make 错误链", s, e))
    else:
        sections.append(("日志尾部", max(0, total - 100), total))

    # 工作流追加的 stage 库检查常落在 +80 行窗口之外，单独截取；
    # 若已在 Make 错误链段内则跳过（避免重复）
    stage_idx = -1
    for i, line in enumerate(lines):
        if "=== stage 关键库检查 ===" in line:
            stage_idx = i
            break
    if stage_idx >= 0:
        in_chain = False
        for _, cs, ce in sections:
            if cs <= stage_idx < ce:
                in_chain = True
                break
        if not in_chain:
            sections.append(("Stage 库检查", stage_idx, min(total, stage_idx + 20)))

    text_parts = []
    for title, s, e in sections:
        text_parts.append(f"=== {title} ===")
        text_parts.append("\n".join(lines[s:e]))
    text = "\n".join(text_parts)

    if len(text) > args.max_chars:
        text = text[:args.max_chars]

    if failed_comp:
        header = f"### 失败组件: {failed_comp} ###\n"
        header += f"### PHASE1: {','.join(phase1_list) if phase1_list else '(无)'} ###\n"
        text = header + text
        print(f"🔧 失败组件: {failed_comp} (phase1={len(phase1_list)} 个组件已成功)")
        if first_err_idx >= 0 and first_err_idx != last_err_idx:
            print(f"🎯 定位到组件内首个错误: 行 {first_err_idx + 1}")
    elif last_dir:
        print(f"ℹ️ 最后进入组件目录: {last_dir}（未捕获错误行，按保守处理）")

    Path(args.output).write_text(text, encoding="utf-8")
    print(f"✅ 已提取错误日志: {args.output} ({len(text)} chars)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
