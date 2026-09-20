"""配置键诚实性测试。

背景：`configs/config.yaml` 曾长期包含一批"写了但没人读"的键
（general.auto_update / proxy.* / docker.auto_clean / panels.* 端口 ...）。
用户改了这些开关却完全不生效，比缺功能更伤信任。

本测试把"配置文件里的每个键都必须有真实读取点"固化为断言：
新增配置项时若不接线，CI 直接失败。
"""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / 'configs' / 'config.yaml'

# 运行时代码位置（配置只可能在这两处被读取）
CODE_GLOBS = ('fusion.sh', 'src/**/*.sh')
# 已接线但读取点写法特殊、无法用 CONFIG_<section>_<key> 直接匹配的键（当前不存在，
# 保留此集合是为了将来有正当理由时可以显式登记，而不是偷偷放宽断言）。
EXPLICIT_ALLOWLIST = set()

SECTION_RE = re.compile(r'^([a-zA-Z_][a-zA-Z0-9_]*):\s*(?:#.*)?$')
KEY_RE = re.compile(r'^\s+([a-zA-Z_][a-zA-Z0-9_]*):\s*(.*)$')


def declared_keys():
    """返回 config.yaml 中声明的 (section, key) 列表（忽略注释行）。"""
    keys = []
    section = None
    for line in CONFIG.read_text(encoding='utf-8').splitlines():
        if not line.strip() or line.lstrip().startswith('#'):
            continue
        section_match = SECTION_RE.match(line)
        if section_match:
            section = section_match.group(1)
            continue
        key_match = KEY_RE.match(line)
        if key_match and section:
            keys.append((section, key_match.group(1)))
    return keys


def code_text():
    parts = []
    for pattern in CODE_GLOBS:
        for path in sorted(ROOT.glob(pattern)):
            if path.is_file():
                parts.append(path.read_text(encoding='utf-8', errors='replace'))
    return '\n'.join(parts)


class ConfigHonesty(unittest.TestCase):
    def test_config_file_exists_and_non_trivial(self):
        self.assertTrue(CONFIG.is_file(), 'configs/config.yaml 缺失')
        self.assertGreaterEqual(len(declared_keys()), 3, 'config.yaml 至少应声明 3 个键')

    def test_every_declared_key_has_a_reader(self):
        """每个声明的键都必须在运行时代码里以 $CONFIG_<section>_<key> 形式被读取。"""
        source = code_text()
        missing = []
        for section, key in declared_keys():
            var = f'CONFIG_{section}_{key}'
            if var in EXPLICIT_ALLOWLIST:
                continue
            if var not in source:
                missing.append(f'{section}.{key} -> 未找到读取点 ${var}')
        self.assertEqual(missing, [], '以下配置键写了但不会被读取，请接线或删除：\n  ' + '\n  '.join(missing))

    def test_no_decorative_auto_update_key(self):
        """`general.auto_update` 是误导性开关的代表：真正的开关是 `update --cron`。

        配置里写了 true 不会开启自动更新，因此该键不得再出现在 config.yaml 中。
        """
        keys = {f'{s}.{k}' for s, k in declared_keys()}
        self.assertNotIn('general.auto_update', keys,
                         'general.auto_update 不会被读取；自动更新请使用 fusionbox update --cron')

    def test_config_documents_out_of_scope_settings(self):
        """不被 config 控制的设置，必须在文件里明确说明它们的真实归属。"""
        text = CONFIG.read_text(encoding='utf-8')
        self.assertIn('不由本文件控制', text,
                      'config.yaml 需要明确列出不由它控制的设置，避免用户误以为写了就生效')

    def test_loader_reads_general_color(self):
        """general.color 必须在 common.sh 的 _load_config 中被消费（关掉 ANSI）。"""
        common = (ROOT / 'src' / 'lib' / 'common.sh').read_text(encoding='utf-8')
        self.assertIn('CONFIG_general_color', common)
        self.assertIn('F_COLOR', common)


if __name__ == '__main__':
    unittest.main(verbosity=2)
