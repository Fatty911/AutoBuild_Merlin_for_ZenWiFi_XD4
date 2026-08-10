# -*- coding: utf-8 -*-
"""XD4 构建工作流步骤自检（防止 .trx/.w 类"本地手动 make 未暴露"的回归）。

覆盖：
1. validate_build_output.find_firmware：机型标识全文搜索（回归：runner 产物
   ~60MB UBI 标识不在前 128KB）、错误机型拒绝
2. check_firmware_size：大小阈值
3. compute_build_info 步骤的固件选择 shell 逻辑（ls image/*.w | grep -v cferom）
"""

import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "custom_scripts"))

import validate_build_output as vbo  # noqa: E402

XD4_MARKER = b"RT-AX56_XD4,3.0.0.4,386"
SDK = "src-rt-5.02axhnd.675x"


class FindFirmwareTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.ws = Path(self.tmp.name)
        image_dir = self.ws / "asuswrt-bcm" / "release" / SDK / "image"
        image_dir.mkdir(parents=True)
        vbo.WORKSPACE = self.ws
        vbo.SOURCE_DIR = self.ws / "asuswrt-bcm"
        vbo.SDK_DIR = SDK

    def tearDown(self):
        self.tmp.cleanup()

    def make_fw(self, name, size_mb, marker=XD4_MARKER, marker_at_tail=False):
        p = vbo.SOURCE_DIR / "release" / SDK / "image" / name
        data = bytearray(b"\x00" * int(size_mb * 1024 * 1024))
        if marker:
            if marker_at_tail:
                data[-len(marker):] = marker
            else:
                data[:len(marker)] = marker
        p.write_bytes(bytes(data))
        return p

    def test_finds_firmware_with_model_marker_in_head(self):
        self.make_fw("3.0.0.4_RTAX56XD4_1_pureubi.w", 11)
        fw = vbo.find_firmware("RT-AX56_XD4", 10)
        self.assertEqual(len(fw), 1)

    def test_finds_firmware_when_marker_beyond_128k(self):
        """回归保护：runner 产物机型标识不在前 128KB，必须全文搜索（2026-08-10 修复）"""
        self.make_fw("3.0.0.4_RTAX56XD4_1_pureubi.w", 60, marker_at_tail=True)
        fw = vbo.find_firmware("RT-AX56_XD4", 10)
        self.assertEqual(len(fw), 1)

    def test_rejects_wrong_model(self):
        self.make_fw("3.0.0.4_RTAX56U_1_pureubi.w", 11, marker=b"RT-AX56U,3.0.0.4,386")
        fw = vbo.find_firmware("RT-AX56_XD4", 10)
        self.assertEqual(len(fw), 0)

    def test_no_firmware_at_all(self):
        fw = vbo.find_firmware("RT-AX56_XD4", 10)
        self.assertEqual(len(fw), 0)


class FirmwareSizeTests(unittest.TestCase):
    def test_accepts_large_enough(self):
        with tempfile.NamedTemporaryFile(suffix=".w", delete=False) as fh:
            fh.truncate(11 * 1024 * 1024)
            p = Path(fh.name)
        try:
            self.assertTrue(vbo.check_firmware_size(p, 10))
        finally:
            p.unlink()

    def test_rejects_too_small(self):
        with tempfile.NamedTemporaryFile(suffix=".w", delete=False) as fh:
            fh.truncate(5 * 1024 * 1024)
            p = Path(fh.name)
        try:
            self.assertFalse(vbo.check_firmware_size(p, 10))
        finally:
            p.unlink()


class ComputeBuildInfoShellTests(unittest.TestCase):
    """compute_build_info 步骤的固件选择逻辑（.w 格式、排除 cferom）"""

    @staticmethod
    def run_selector(td):
        return subprocess.run(
            ["bash", "-lc", "ls image/*.w 2>/dev/null | grep -v cferom | head -1"],
            cwd=td, capture_output=True, text=True, check=True, timeout=30,
        )

    def test_selects_non_cferom_w(self):
        with tempfile.TemporaryDirectory() as td:
            image = Path(td) / "image"
            image.mkdir()
            (image / "3.0.0.4_RTAX56XD4_1_cferom_pureubi.w").write_bytes(b"x")
            (image / "3.0.0.4_RTAX56XD4_1_pureubi.w").write_bytes(b"y")
            # 旧 .trx 假设残留防护：即使存在 .trx 也不应被选中
            (image / "3.0.0.4_RTAX56XD4_1.trx").write_bytes(b"z")
            out = self.run_selector(td)
            self.assertEqual(
                out.stdout.strip(),
                "image/3.0.0.4_RTAX56XD4_1_pureubi.w",
            )
            self.assertNotIn(".trx", out.stdout)
            time.sleep(0.2)  # Windows: bash 子进程 cwd 句柄延迟释放

    def test_no_w_files_returns_empty(self):
        with tempfile.TemporaryDirectory() as td:
            image = Path(td) / "image"
            image.mkdir()
            out = self.run_selector(td)
            self.assertEqual(out.stdout.strip(), "")
            time.sleep(0.2)


if __name__ == "__main__":
    unittest.main()
