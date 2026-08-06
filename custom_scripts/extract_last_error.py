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
    re.compile(r"(?:error|fatal error|undefined reference|No such file|not found|command not found)",
               re.IGNORECASE),
    re.compile(r"make\[\d+\]: \*\*\*"),
    re.compile(r"configure: error"),
    re.compile(r"cc1?:\s*(?:error|fatal)"),
    re.compile(r"collect2: error"),
]


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

    Path(args.output).write_text(text, encoding="utf-8")
    print(f"✅ 已提取错误日志: {args.output} ({len(text)} chars, 行 {start}-{start + len(context)})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
