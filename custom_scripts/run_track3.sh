#!/bin/bash
set -euo pipefail

# Single-track OpenCode Agent Runner
# This script is called from AI_Auto_Fix_Monitor.yml
# Expected env vars: WORKFLOW_RUN_ID, WORKFLOW_NAME, WORKFLOW_PATH, REPOSITORY
# Plus all API keys needed by pick_best_model.py

git config --local --unset-all http.https://github.com/.extraheader || true

git fetch origin main
git checkout main || git checkout -b main
git pull --ff-only origin main

if [ ! -f "last_error.log" ]; then
  echo "未找到 last_error.log，尝试重新下载 error-log artifact..."
  gh run download "${WORKFLOW_RUN_ID}" -n error-log || true
fi

if [ ! -s "last_error.log" ]; then
  echo "::error::无法获取有效的构建错误日志，拒绝盲修"
  exit 1
fi

WORKFLOW_YML="${GITHUB_WORKSPACE}/${WORKFLOW_PATH}"
WORKFLOW_FILENAME=$(basename "$WORKFLOW_YML")

echo "==== 收集可用模型 ===="
python custom_scripts/pick_best_model.py --ranked > fallback_models.txt 2>/dev/null || true
python custom_scripts/dmxapi_meta_router.py --list > dmxapi_models.txt 2>/dev/null || true
# 硬编码候选排最前（经本机/runner 验证高概率可用的端点，避免 --ranked 榜单过滤漏掉）
cat > extra_models.txt <<'EOF'
zhipu/GLM-5.1
volcengine-coding/glm-5.2
kimi-coding-plan/k3
deepseek/deepseek-v4-flash
scnet/GLM-5.2
alibaba-tokenplan/qwen3.8-max-preview
volcengine-agentplan/kimi-k3
qianfan-coding-plan/glm-5.1
opencode-go/gpt-5.6-luna
zenmux/deepseek-v4-flash-free
EOF
cat extra_models.txt fallback_models.txt dmxapi_models.txt | awk '!x[$0]++' > models_to_try.txt

if [ ! -s models_to_try.txt ]; then
  echo "::error::无可用模型，OpenCode 自动修复终止"
  exit 1
fi

echo "将要尝试的模型优先级列表:"
cat models_to_try.txt

RUNTIME_FILES=(
  ".leaderboard_cache.json"
  ".model_resolution_cache.json"
  ".openrouter_free_models_cache.json"
  ".zen_free_models_cache.json"
  "models_to_try.txt"
  "dmxapi_models.txt"
  "fallback_models.txt"
  "extra_models.txt"
  "opencode.json"
  "opencode_output.log"
  "prompt.txt"
)

stage_source_changes() {
  git add -A
  git reset --quiet HEAD -- "${RUNTIME_FILES[@]}" 2>/dev/null || true
  ! git diff --cached --quiet
}

discard_runtime_files() {
  git restore --staged -- "${RUNTIME_FILES[@]}" 2>/dev/null || true
  git restore --worktree -- "${RUNTIME_FILES[@]}" 2>/dev/null || true
  rm -f "${RUNTIME_FILES[@]}"
}

reset_attempt_changes() {
  git restore --staged -- . 2>/dev/null || true
  git restore --worktree -- . 2>/dev/null || true
  git clean -fd \
    -e last_error.log \
    -e models_to_try.txt \
    -e fallback_models.txt \
    -e dmxapi_models.txt \
    -e extra_models.txt \
    -e prompt.txt \
    -e opencode_output.log \
    -e opencode.json \
    -e '*.protected_backup'
}

# ── 保护关键文件：AI 运行前备份，防止 AI 误删 ──
PROTECTED_FILES=(
  "oh-my-openagent.json"
  "AGENTS.md"
  "ai_tools/opencode/opencode.json"
  "ai_tools/opencode/oh-my-openagent.json"
)
for f in "${PROTECTED_FILES[@]}"; do
  [ -f "$f" ] && cp "$f" "${f}.protected_backup"
done

cat > prompt.txt <<EOF
分析 last_error.log 和失败工作流 ${WORKFLOW_FILENAME}，找到根因并做最小修复。
${CLASSIFICATION:+错误分类: ${CLASSIFICATION}
分类说明: ${REASON}
请围绕该分类定位根因（transient/upstream 类不会走到这里；dependency=依赖或构建环境问题，build_error=编译错误，gate=质量门/产物校验失败）。}
要求：
1. 只修复本次 Merlin (asuswrt-bcm 386 分支) 构建失败直接涉及的文件（.github/workflows/ 与 custom_scripts/），不修改其它无关文件。
2. 不修改或删除 AGENTS.md、README.md。
3. 不删除质量门、Release 发布、更新检查、清理等关键步骤。
4. 不提交缓存、模型列表、日志或临时文件。
5. 上游源码在 asuswrt-bcm/ 子目录（每次构建重新浅克隆 SWRT-dev/asuswrt-bcm），不要直接改其中的文件；如需对上游打补丁，应修改 custom_scripts/patch_xd4_source.sh 或构建工作流。
6. 修复后运行相关语法检查（validate_syntax.py）；如果无法确定根因，不要制造无依据改动。
EOF

FIX_SUCCEEDED=false
FIXER_MODEL=""
MAX_MODEL_TRIES=8
MODEL_TRIES=0
MODEL_TIMEOUT=600
DMXAPI_BROKEN=false
# 用 fd 3 读取模型列表，避免循环内 opencode 等子进程消费 stdin 导致循环提前 EOF
exec 3< models_to_try.txt
while read -r FULL_MODEL <&3; do
  [ -z "$FULL_MODEL" ] && continue

  PROVIDER=$(echo "$FULL_MODEL" | cut -d '/' -f 1)

  if [ "$DMXAPI_BROKEN" = "true" ] && [ "$PROVIDER" = "dmxapi" ]; then
    echo "⏭️ DMXAPI 已标记不可用，跳过: $FULL_MODEL"
    continue
  fi

  MODEL_TRIES=$((MODEL_TRIES + 1))
  if [ "$MODEL_TRIES" -gt "$MAX_MODEL_TRIES" ]; then
    echo "已尝试 $MAX_MODEL_TRIES 个模型，停止继续尝试"
    break
  fi

  MODEL_NAME=$(echo "$FULL_MODEL" | cut -d '/' -f 2-)
  echo "=========================================================="
  echo "当前尝试模型: $FULL_MODEL"
  echo "=========================================================="

  reset_attempt_changes

  if [ "$PROVIDER" = "dmxapi" ]; then
    python custom_scripts/dmxapi_meta_router.py --config-opencode "$PROVIDER" "$MODEL_NAME" > opencode.json
    mkdir -p ~/.config/opencode
    python custom_scripts/dmxapi_meta_router.py --config-omo > ~/.config/opencode/oh-my-openagent.json
  else
    python custom_scripts/pick_best_model.py --opencode-config-for "$PROVIDER" "$MODEL_NAME" > opencode.json
    mkdir -p ~/.config/opencode
    python custom_scripts/dmxapi_meta_router.py --config-omo-generic "$PROVIDER" "$MODEL_NAME" > ~/.config/opencode/oh-my-openagent.json
  fi

  if ! python3 -c "import json; json.load(open('opencode.json'))" 2>/dev/null; then
    echo "::warning::opencode.json 不是合法 JSON，跳过此模型"
    continue
  fi

  API_KEY=$(python3 -c "import json; c=json.load(open('opencode.json')); p=c.get('provider',{}); v=list(p.values())[0] if p else {}; print(v.get('options',{}).get('apiKey',''))")
  if [ -z "$API_KEY" ]; then
    echo "::warning::⏭️ API key 为空，跳过: $FULL_MODEL"
    continue
  fi

  cp opencode.json ~/.config/opencode/opencode.json
  RUN_TITLE="auto-fix-${WORKFLOW_RUN_ID}-${MODEL_TRIES}"
  OPENCODE_EXIT=0
  timeout "$MODEL_TIMEOUT" opencode run \
    --model "$FULL_MODEL" \
    --format default \
    --dir "$GITHUB_WORKSPACE" \
    --title "$RUN_TITLE" \
    "$(cat prompt.txt)" < /dev/null 2>&1 | tee opencode_output.log || OPENCODE_EXIT=$?
  echo "opencode 退出码: $OPENCODE_EXIT"

  if [ "$OPENCODE_EXIT" -ne 0 ]; then
    echo "::warning::模型调用失败或超时，回滚本次尝试"
    if [ "$PROVIDER" = "dmxapi" ] && grep -qiE "certificate has expired|SSL|TLS" opencode_output.log; then
      DMXAPI_BROKEN=true
    fi
    reset_attempt_changes
    continue
  fi

  # 只匹配 opencode/API 的"唯一错误签名"（模型正文里自然出现的 401/429/
  # balance/quota/Bad Request/Unauthorized 等词不算失败信号——实测 #45 中
  # 模型正常分析文本含这些词导致误回滚，正确的修复被丢弃；只有 opencode
  # 会话级错误才有这些独特签名）
  if grep -qiE "ProviderModelNotFoundError|Error: Model not found|\[session\.error\]|UnknownError|certificate has expired|ETIMEDOUT|Failed to create session|余额不足" opencode_output.log; then
    echo "::warning::模型输出包含明确失败信号，回滚本次尝试"
    grep -iE "ProviderModelNotFoundError|Error: Model not found|\[session\.error\]|UnknownError|certificate has expired|ETIMEDOUT|Failed to create session|余额不足" opencode_output.log | head -3 || true
    reset_attempt_changes
    continue
  fi

  if stage_source_changes; then
    FIX_SUCCEEDED=true
    FIXER_MODEL="$FULL_MODEL"
    echo "✅ $FULL_MODEL 产生了非缓存源码修改"
    break
  fi

  echo "⚠️ $FULL_MODEL 未产生非缓存源码修改，继续尝试"
  reset_attempt_changes
done
exec 3<&-  # 关闭模型列表 fd

# ── 检查是否最终修复成功 ──
if [ "$FIX_SUCCEEDED" != "true" ]; then
  echo "::error::所有模型尝试完毕，OpenCode 自动修复失败，不提交任何更改"
  exit 1
fi

git config user.name "Fatty911"
git config user.email "xuerui911@gmail.com"

# ── 恢复被 AI 误删的关键文件 ──
for f in "${PROTECTED_FILES[@]}"; do
  if [ -f "${f}.protected_backup" ] && ! cmp -s "$f" "${f}.protected_backup"; then
    echo "⚠️ AI 修改或删除了受保护文件 $f，正在恢复..."
    cp "${f}.protected_backup" "$f"
  fi
done
find . -name '*.protected_backup' -delete

# ── 防止 AI 改到其他工作流文件 ──
echo "=== 🔒 工作流文件隔离检查 ==="
TARGET_WF="$(basename "$WORKFLOW_YML")"
stage_source_changes || true
CHANGED_WF_FILES=$(git diff --cached --name-only | grep '^.github/workflows/' || true)
if [ -n "$CHANGED_WF_FILES" ]; then
  echo "$CHANGED_WF_FILES" | while read -r wf; do
    wf_name=$(basename "$wf")
    if [ "$wf_name" != "$TARGET_WF" ]; then
      echo "⚠️ AI 意外修改了非目标工作流: $wf_name → 正在恢复"
      git restore --source=HEAD --staged --worktree -- "$wf" 2>/dev/null || true
    fi
  done
else
  echo "✅ AI 未修改任何工作流文件，隔离检查通过"
fi

# ── 文件数量异常检测（防 gh repo sync --force 等意外大规模删除）──
echo "=== 📊 文件数量异常检测 ==="
WORKFLOW_BEFORE=$(git ls-tree -r --name-only HEAD -- .github/workflows | grep -E '\.ya?ml$' | wc -l)
SCRIPTS_BEFORE=$(git ls-tree -r --name-only HEAD -- custom_scripts | wc -l)
WORKFLOW_AFTER=$(find .github/workflows -type f \( -name "*.yml" -o -name "*.yaml" \) | wc -l)
SCRIPTS_AFTER=$(find custom_scripts -type f -not -path '*/__pycache__/*' | wc -l)

echo "工作流文件: ${WORKFLOW_BEFORE} → ${WORKFLOW_AFTER}"
echo "脚本文件:   ${SCRIPTS_BEFORE} → ${SCRIPTS_AFTER}"

WF_PCT=$(( (WORKFLOW_BEFORE - WORKFLOW_AFTER) * 100 / (WORKFLOW_BEFORE + 1) ))
SC_PCT=$(( (SCRIPTS_BEFORE - SCRIPTS_AFTER) * 100 / (SCRIPTS_BEFORE + 1) ))

if [ "$WF_PCT" -ge 20 ] || [ "$SC_PCT" -ge 20 ]; then
  echo "::error::❌ 文件数量异常减少 ≥20%！可能发生了大规模误删（如 gh repo sync --force）。回滚修改并报告异常。"
  echo "::error::工作流: ${WORKFLOW_BEFORE}→${WORKFLOW_AFTER} (${WF_PCT}%)，脚本: ${SCRIPTS_BEFORE}→${SCRIPTS_AFTER} (${SC_PCT}%)"
  reset_attempt_changes
  exit 1
fi
echo "✅ 文件数量正常"

discard_runtime_files
if ! stage_source_changes; then
  echo "::error::AI 运行完成但未产生任何代码更改，修复可能无效"
  exit 1
fi

# === 推送前语法校验 ===
echo "=== 🔍 推送前语法校验 ==="
python custom_scripts/validate_syntax.py
VALIDATION_EXIT=$?
if [ $VALIDATION_EXIT -ne 0 ]; then
  echo "::error::❌ 语法校验失败，拒绝推送，回滚修改"
  reset_attempt_changes
  exit 1
fi
echo "✅ 语法校验通过，准备提交"

# === 多模型共识评审：N=2 / M=2，缺票或调用异常一律拒绝 ===
echo "=== 🔍 多模型共识评审 ==="
ERROR_LOG_CONTENT=$(cat last_error.log 2>/dev/null || echo "No error log")
REVIEW_EXIT=0
REVIEW_OUTPUT=$(
  FIXER_MODEL="$FIXER_MODEL" REVIEW_TOTAL=2 REVIEW_THRESHOLD=2 \
    python custom_scripts/multi_agent_review.py review --error "$ERROR_LOG_CONTENT" 2>&1
) || REVIEW_EXIT=$?
echo "$REVIEW_OUTPUT"
if [ "$REVIEW_EXIT" -ne 0 ] || ! echo "$REVIEW_OUTPUT" | grep -q '^RESULT: PASS$'; then
  echo "::error::❌ 多模型共识评审未通过，回滚修改"
  reset_attempt_changes
  exit 1
fi
echo "✅ 多模型共识评审通过，准备提交"

git commit -m "Auto-fix build error with OpenCode Deep Repair"
git remote set-url origin "https://x-access-token:${ACTIONS_TRIGGER_PAT}@github.com/${REPOSITORY}.git"

# === Push with retry: rebase + 429 handling + permission errors ===
echo "=== 推送代码到远程仓库 ==="
PUSH_MAX_RETRIES=5
PUSH_RETRY_COUNT=0
PUSH_SUCCESS=false

while [ $PUSH_RETRY_COUNT -lt $PUSH_MAX_RETRIES ] && [ "$PUSH_SUCCESS" = "false" ]; do
  PUSH_RETRY_COUNT=$((PUSH_RETRY_COUNT + 1))
  echo "推送尝试 $PUSH_RETRY_COUNT / $PUSH_MAX_RETRIES..."
  
  echo "=== 拉取远程最新提交 (rebase) ==="
  if ! git pull --rebase origin main; then
    git rebase --abort 2>/dev/null || true
    echo "::error::远程分支发生冲突，拒绝自动选择任一侧内容"
    exit 1
  fi
  
  PUSH_OUTPUT=$(git push origin HEAD:main 2>&1) && PUSH_EXIT=0 || PUSH_EXIT=$?
  echo "推送输出: $PUSH_OUTPUT"
  echo "推送退出码: $PUSH_EXIT"
  
  if [ $PUSH_EXIT -eq 0 ]; then
    PUSH_SUCCESS=true
    echo "✅ 推送成功"
  else
    if echo "$PUSH_OUTPUT" | grep -qiE "429|QUOTA_EXHAUSTED|rate limit|Too Many Requests|slow down"; then
      echo "⚠️ 检测到 HTTP 429 (配额耗尽/速率限制)，等待后重试..."
      # 指数退避: 15s, 30s, 60s, 120s, 240s
      WAIT_TIME=$((15 * (2 ** (PUSH_RETRY_COUNT - 1))))
      echo "等待 ${WAIT_TIME} 秒后重试..."
      sleep $WAIT_TIME
    elif echo "$PUSH_OUTPUT" | grep -qiE "rejected|non-fast-forward|fetch first|cannot lock ref|updates were rejected"; then
      echo "⚠️ 推送被拒绝（远程有新提交），下次循环将 pull --rebase 后重试..."
    elif echo "$PUSH_OUTPUT" | grep -qiE "GitHub App|workflows.*permission|without.*workflows|remote rejected.*workflow"; then
      echo "::error::推送 token 缺少 workflows 权限，拒绝丢弃部分修复后伪装成功"
      exit 1
    else
      echo "::warning::推送失败 (未知原因): $PUSH_OUTPUT"
      sleep 10
    fi
  fi
done

if [ "$PUSH_SUCCESS" = "false" ]; then
  echo "::error::推送失败，已尝试 $PUSH_MAX_RETRIES 次仍失败"
  echo "⚠️ 修复代码已提交到本地，但因 GitHub API 限制无法推送"
  echo "请手动检查并推送修复:"
  echo "  1. 检查 git status"
  echo "  2. 运行 git pull --rebase origin main"
  echo "  3. 运行 git push origin main"
  exit 1
fi

echo "OpenCode 修复成功并已推送"

# ── 验证闭环：修复推送会触发 Prepare（push paths 含 custom_scripts/** 与
#    Build_Merlin_Firmware.yml）→ Prepare 成功后再 workflow_run 触发 Build 自动验证。
#    不再手动 dispatch Build：否则与 Prepare 链触发的 Build 并发互杀（concurrency
#    cancel-in-progress），浪费一次 2-4h 构建。若确实需要立即验证，请手动 dispatch。
rm -f last_error.log
