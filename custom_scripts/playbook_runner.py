#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Merlin XD4 构建错误预案调度器（Error Playbook Runner）

本地调试与线上 AI_Auto_Fix_Monitor 共用。分类决策复用
classify_build_failure.py（transient/upstream 不修），本工具在其上补充
组件归类、预案查询与 history 沉淀：

  1. monitor      : 读 last_error.log → classify_build_failure 分类 →
                    输出 GITHUB_OUTPUT 兼容字段（classification/should_fix/reason）
                    并记录 history.jsonl（随仓库提交沉淀）
  2. classify     : 同 monitor，输出 JSON 到 stdout/文件（本地调试用）
  3. record       : 记录 resolved_by 结果（AI 修复后更新历史）
  4. upstream-check: 本地有 asuswrt-bcm 工作区时检测相关路径上游改动

用法：
  python playbook_runner.py --mode monitor --log last_error.log [--json-out cls.json]
  python playbook_runner.py --mode record --result cls.json --source monitor:<run_id>
  python playbook_runner.py --mode upstream-check --log last_error.log --openwrt-dir asuswrt-bcm
"""

import argparse
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent
CATALOG_DIR = REPO_ROOT / "ai_tools" / "error_catalog"
CATALOG_FILE = CATALOG_DIR / "catalog.yaml"
HISTORY_FILE = CATALOG_DIR / "history.jsonl"

sys.path.insert(0, str(SCRIPT_DIR))
try:
    import classify_build_failure as cbf  # noqa: E402
except Exception:  # noqa: BLE001
    cbf = None


# classification → (类别 id, 组件, 是否触发 AI)
CLASS_MAP = {
    "no_logs": ("no_logs", "build:process", False),
    "transient": ("transient", "infra:network", False),
    "upstream": ("upstream", "upstream:merlin", False),
    "dependency": ("dependency", "build:process", True),
    "build_error": ("build_error", "upstream:merlin", True),
    "gate": ("gate", "build:process", True),
    "prep_env": ("prep_env", "build:artifact", True),
}


def load_catalog():
    try:
        import yaml
        with open(CATALOG_FILE, "r", encoding="utf-8") as fh:
            return yaml.safe_load(fh)
    except Exception as exc:  # noqa: BLE001
        print(f"::warning::加载 catalog.yaml 失败: {exc}", file=sys.stderr)
        return None


def catalog_lookup(catalog, category_id):
    if not catalog:
        return None
    for entry in catalog.get("categories", []):
        if entry.get("id") == category_id:
            return entry
    return None


def classify(log_text):
    """分类：优先用 classify_build_failure，缺失时退化为简单规则。"""
    if cbf is not None:
        classification, should_fix, reason = cbf.classify(log_text)
    else:
        classification, should_fix, reason = "build_error", True, "classify_build_failure 不可用，保守走 AI"
    category, component, _ = CLASS_MAP.get(classification, ("build_error", "unknown", True))
    return {
        "signature": classification,
        "category": category,
        "component": component,
        "should_fix": should_fix,
        "reason": reason,
    }


def record_entry(result, source, resolved_by="pending", extra=None):
    HISTORY_FILE.parent.mkdir(parents=True, exist_ok=True)
    entry = {
        "ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "source": source,
        "signature": result.get("signature", "unknown"),
        "category": result.get("category", "unknown"),
        "component": result.get("component", "unknown"),
        "playbook_id": result.get("playbook_id", ""),
        "resolved_by": resolved_by,
        "reason": result.get("reason", "")[:200],
    }
    if extra:
        entry.update(extra)
    with open(HISTORY_FILE, "a", encoding="utf-8") as fh:
        fh.write(json.dumps(entry, ensure_ascii=False) + "\n")
    return entry


def enrich_with_catalog(result):
    catalog = load_catalog()
    entry = catalog_lookup(catalog, result["category"])
    result["category_name"] = entry.get("name", result["category"]) if entry else result["category"]
    result["playbook_id"] = entry.get("playbook", {}).get("id", "") if entry else ""
    result["playbook_name"] = entry.get("playbook", {}).get("name", "") if entry else ""
    result["ai_fallback"] = result["should_fix"]
    return result


def upstream_check(log_text, source_dir, signature):
    """检测相关路径的上游最近改动（patch 目标/组件目录）。"""
    src = Path(source_dir)
    if not (src / ".git").exists():
        return {"changed": False, "paths": [], "commits": [], "note": "源码目录不是 git 仓库"}
    paths = set()
    for m in re.finditer(r"(?:release/src/[A-Za-z0-9_./-]+|package/[A-Za-z0-9_./-]+|target/[A-Za-z0-9_./-]+)", log_text):
        paths.add(m.group(0))
    commits, changed = [], False
    for p in sorted(paths)[:8]:
        try:
            out = subprocess.run(
                ["git", "-C", str(src), "log", "--oneline", "-5", "--", p],
                capture_output=True, text=True, timeout=20,
            ).stdout.strip()
        except Exception:  # noqa: BLE001
            continue
        if out:
            changed = True
            commits.append({"path": p, "log": out.splitlines()})
    return {"changed": changed, "paths": sorted(paths), "commits": commits}


def read_log(path):
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        return fh.read()


def cmd_monitor(args):
    """Monitor 兼容模式：输出 GITHUB_OUTPUT 字段 + 写 history。"""
    log_text = read_log(args.log)
    result = enrich_with_catalog(classify(log_text))
    if args.json_out:
        with open(args.json_out, "w", encoding="utf-8") as fh:
            json.dump(result, fh, ensure_ascii=False, indent=2)
    if os.environ.get("GITHUB_OUTPUT"):
        with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as fh:
            fh.write(f"classification={result['signature']}\n")
            fh.write(f"should_fix={str(result['should_fix']).lower()}\n")
            fh.write(f"reason={result['reason']}\n")
            fh.write(f"category={result['category']}\n")
            fh.write(f"component={result['component']}\n")
    run_id = os.environ.get("RUN_ID") or args.run_id or ""
    record_entry(result, source=f"monitor:{run_id}", resolved_by="pending",
                 extra={"run_id": run_id} if run_id else None)
    print(json.dumps(result, ensure_ascii=False))
    return 0


def cmd_classify(args):
    log_text = read_log(args.log)
    result = enrich_with_catalog(classify(log_text))
    if args.json_out:
        with open(args.json_out, "w", encoding="utf-8") as fh:
            json.dump(result, fh, ensure_ascii=False, indent=2)
    print(json.dumps(result, ensure_ascii=False))
    return 0


def cmd_record(args):
    if args.result:
        result = json.load(open(args.result, encoding="utf-8"))
    else:
        result = {
            "signature": args.signature or "unknown",
            "category": args.category or "unknown",
            "component": args.component or "unknown",
            "reason": args.reason or "",
        }
    entry = record_entry(result, source=args.source or "manual",
                         resolved_by=args.resolved_by or "pending",
                         extra={"run_id": args.run_id} if args.run_id else None)
    print(f"已记录: {json.dumps(entry, ensure_ascii=False)}")
    return 0


def cmd_upstream_check(args):
    log_text = read_log(args.log)
    result = classify(log_text)
    if result["category"] not in ("build_error", "prep_env"):
        print(json.dumps({"changed": False, "category": result["category"],
                          "note": "非路径敏感类别，跳过上游回归检测"}, ensure_ascii=False))
        return 0
    check = upstream_check(log_text, args.openwrt_dir, result["signature"])
    check["signature"] = result["signature"]
    check["category"] = result["category"]
    if args.json_out:
        with open(args.json_out, "w", encoding="utf-8") as fh:
            json.dump(check, fh, ensure_ascii=False, indent=2)
    print(json.dumps(check, ensure_ascii=False))
    return 0


def main():
    parser = argparse.ArgumentParser(description="Merlin XD4 构建错误预案调度器")
    parser.add_argument("--mode", required=True,
                        choices=["monitor", "classify", "record", "upstream-check"],
                        help="monitor=Monitor兼容(输出GITHUB_OUTPUT+记录) | classify=分类JSON | record=记录结果 | upstream-check=上游回归检测")
    parser.add_argument("--log", help="last_error.log 路径")
    parser.add_argument("--json-out", help="结果 JSON 输出路径")
    parser.add_argument("--openwrt-dir", help="本地 asuswrt-bcm git 工作区")
    parser.add_argument("--result", help="record 模式：classify 输出的 JSON 文件")
    parser.add_argument("--signature", help="record 模式：错误签名（无 --result 时）")
    parser.add_argument("--category", help="record 模式：类别 id")
    parser.add_argument("--component", help="record 模式：组件")
    parser.add_argument("--reason", help="record 模式：一句话原因")
    parser.add_argument("--source", default="manual", help="record 模式：来源（monitor:<run_id>/ai/manual）")
    parser.add_argument("--resolved-by", default="pending",
                        help="record 模式：pending/ai/ai_failed/manual")
    parser.add_argument("--run-id", help="关联的 GitHub Actions run id")
    args = parser.parse_args()

    if args.mode == "monitor":
        return cmd_monitor(args)
    if args.mode == "classify":
        return cmd_classify(args)
    if args.mode == "record":
        return cmd_record(args)
    if args.mode == "upstream-check":
        return cmd_upstream_check(args)
    parser.error("未知模式: %s" % args.mode)
    return 1


if __name__ == "__main__":
    main()
