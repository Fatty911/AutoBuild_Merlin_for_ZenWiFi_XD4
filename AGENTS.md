# Repository Rules

## 非协商发布门禁 (Build Quality Gate)

每次构建发布前必须通过 `custom_scripts/validate_build_output.py --gate`：

1. `.w` 固件文件存在，且固件全文包含预期机型标识（默认 `RT-AX56_XD4`）；机型校验不是依赖文件名匹配
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
- Git 提交作者必须为 `Fatty911 <<已批准的提交邮箱>>`，禁止 bot 身份
- 修改 `custom_scripts/` 下脚本后，本地必须用 Python 语法检查（`python -m py_compile`）验证
- 修改工作流后，本地必须通过 YAML 解析验证（`python -c "import yaml,sys; yaml.safe_load(open(sys.argv[1]))"`）
- 长构建（>1 小时）必须设置 `timeout-minutes`，禁止无限挂起

> 隐私占位符说明：`<已批准的提交邮箱>`指用户已批准的实际提交邮箱，`<禁用的bot关联邮箱>`指被禁止、会关联纯 `bot` 作者身份的邮箱；二者都不是可直接填入 Git 的字面值。实际身份须从私有提交身份信息核对；未能确认时先暂停并请求确认，不猜测或新建身份。本说明不要求修改现有 Git 配置。

