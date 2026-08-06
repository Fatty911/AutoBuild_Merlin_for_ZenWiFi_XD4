# Repository Rules

## 非协商发布门禁 (Build Quality Gate)

每次构建发布前必须通过 `custom_scripts/validate_build_output.py --gate`：

1. 固件文件存在且文件名匹配机型模式（`RT-AX56_XD4_*.trx`）
2. 固件大小 ≥ 10 MB
3. 软件中心源码已集成（`release/src/router/softcenter/Softcenter.asp` 与 `softcenter.sh`）

质量门未通过的固件**禁止**发布 Release 或作为正式产物交付。任何修改构建、合并、
发布或审计逻辑的提交不得削弱该门禁。

## 上游与数据完整性

- 固件源码固定跟踪 `SWRT-dev/asuswrt-bcm` 的 `386` 分支（可通过 workflow_dispatch 选择其他分支，但默认必须 386）
- 构建必须使用 XD4 专用目标 `rt-ax56_xd4`（`BRCM_BOARD_ID="XD4"`），禁止用 RT-AX56U 配置冒充 XD4 固件
- 每次发布必须附带 `.sha256` 校验文件和 `firmware-info.txt`（含上游 commit）

## 工程规范

- 第三方 GitHub Actions 使用 `@main` / `@master` 分支跟踪，禁止 pin commit SHA
- Git 提交作者必须为 `Fatty911 <xuerui911@gmail.com>`，禁止 bot 身份
- 修改 `custom_scripts/` 下脚本后，本地必须用 Python 语法检查（`python -m py_compile`）验证
- 修改工作流后，本地必须通过 YAML 解析验证（`python -c "import yaml,sys; yaml.safe_load(open(sys.argv[1]))"`）
- 长构建（>1 小时）必须设置 `timeout-minutes`，禁止无限挂起
