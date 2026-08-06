#!/usr/bin/env python3
"""清理 workflow run 记录，每个 workflow 每种结论保留最近 N 个。"""

import json
import os
import sys
import urllib.request

KEEP = int(os.environ.get("KEEP_PER_CONCLUSION", "2"))
DRY_RUN = os.environ.get("DRY_RUN", "false").lower() == "true"


def gh_api(method: str, path: str, body: dict | None = None) -> dict | list:
    token = os.environ.get("GITHUB_TOKEN", "")
    url = f"https://api.github.com{path}"
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"Bearer {token}")
    req.add_header("Accept", "application/vnd.github+json")
    try:
        with urllib.request.urlopen(req) as resp:
            raw = resp.read().decode()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        print(f"⚠️ API {method} {path} 失败: {e.code}")
        return {}


def main() -> int:
    repo = os.environ.get("GITHUB_REPOSITORY", "")
    if not repo:
        print("❌ 缺少 GITHUB_REPOSITORY")
        return 1

    workflows = gh_api("GET", f"/repos/{repo}/actions/workflows?per_page=100")
    if not isinstance(workflows, dict) or "workflows" not in workflows:
        print("❌ 获取 workflows 失败")
        return 1

    deleted = 0
    for wf in workflows["workflows"]:
        wf_name = wf["name"]
        # 分页拉取每个 workflow 的 runs
        page = 1
        by_conclusion: dict[str, list[dict]] = {}
        while page <= 10:
            runs = gh_api(
                "GET",
                f"/repos/{repo}/actions/workflows/{wf['id']}/runs?per_page=100&page={page}",
            )
            if not isinstance(runs, dict) or not runs.get("workflow_runs"):
                break
            for r in runs["workflow_runs"]:
                conclusion = r.get("conclusion") or r.get("status") or "unknown"
                by_conclusion.setdefault(conclusion, []).append(r)
            if len(runs["workflow_runs"]) < 100:
                break
            page += 1

        for conclusion, runs in by_conclusion.items():
            runs.sort(key=lambda r: r.get("created_at", ""), reverse=True)
            for r in runs[KEEP:]:
                print(f"删除 run #{r['run_number']} ({conclusion}) [{wf_name}]")
                if not DRY_RUN:
                    gh_api("DELETE", f"/repos/{repo}/actions/runs/{r['id']}")
                    deleted += 1

    print(f"清理完成: 删除 {deleted} 个 run (DRY_RUN={DRY_RUN})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
