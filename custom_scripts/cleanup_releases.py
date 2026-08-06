#!/usr/bin/env python3
"""清理指定 tag 前缀的旧 release，只保留最近 N 个。

用法:
    cleanup_releases.py --prefix Merlin_XD4_ --keep 3
环境变量: GITHUB_REPOSITORY, GITHUB_TOKEN
"""

import argparse
import json
import os
import sys
import urllib.request


def gh_api(method: str, path: str, body: dict | None = None) -> dict | list:
    token = os.environ.get("GITHUB_TOKEN", "")
    url = f"https://api.github.com{path}"
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"Bearer {token}")
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("X-GitHub-Api-Version", "2022-11-28")
    try:
        with urllib.request.urlopen(req) as resp:
            raw = resp.read().decode()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        print(f"⚠️ API {method} {path} 失败: {e.code} {e.read().decode()[:200]}")
        return {}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--prefix", required=True, help="release tag 前缀")
    parser.add_argument("--keep", type=int, default=3, help="保留数量")
    args = parser.parse_args()

    repo = os.environ.get("GITHUB_REPOSITORY", "")
    if not repo:
        print("❌ 缺少 GITHUB_REPOSITORY 环境变量")
        return 1

    releases = gh_api("GET", f"/repos/{repo}/releases?per_page=100")
    if not isinstance(releases, list):
        print("❌ 获取 releases 失败")
        return 1

    # 只处理本工作流创建的 release（tag 前缀匹配）且不是 draft
    mine = [r for r in releases if r.get("tag_name", "").startswith(args.prefix) and not r.get("draft")]
    mine.sort(key=lambda r: r.get("created_at", ""), reverse=True)
    print(f"前缀 '{args.prefix}' 的 release: {len(mine)} 个 (保留 {args.keep} 个)")

    to_delete = mine[args.keep:]
    for r in to_delete:
        print(f"删除 release: {r['tag_name']}")
        gh_api("DELETE", f"/repos/{repo}/releases/{r['id']}")
        # 同时删除 tag
        gh_api("DELETE", f"/repos/{repo}/git/refs/tags/{r['tag_name']}")

    print(f"清理完成: 删除 {len(to_delete)} 个, 保留 {len(mine[:args.keep])} 个")
    return 0


if __name__ == "__main__":
    sys.exit(main())
