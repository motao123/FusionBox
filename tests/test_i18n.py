#!/usr/bin/env python3
"""i18n 双语契约测试。

覆盖：
  1. 语言包一致性（键集合、占位符、非空）与英文包纯净度（不含中文）
  2. L / _tr 取值行为（插值、未知键登记、EN 缺键回落中文）
  3. 语言解析（auto → 由 LANG 决定；_init_lang 兼容别名）
  4. 核心层覆盖率（fusion.sh / install.sh / init.sh / common.sh 无未抽取文案）
  5. install.sh 内置早期表与语言包零漂移
  6. 安装器与运行时共用同一 L 语义
  7. 非交互下 pause 不阻塞（只读输出可被脚本消费）
  8. `fusionbox lang` 命令接线与未知语言退出码
"""
import io
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, 'scripts'))

import i18n_audit  # noqa: E402

# 需要真实 bash 的行为测试：Windows 本地开发机上没有 bash 时跳过（CI/真机必跑）
BASH = shutil.which('bash')
needs_bash = unittest.skipUnless(BASH, '需要 bash（CI 与真机上会执行）')

KEY_RE = re.compile(r'^([A-Z][A-Z0-9_]*)="((?:[^"\\]|\\.)*)"', re.M)


def pack(lang):
    return dict(KEY_RE.findall(
        io.open(os.path.join(ROOT, 'src', 'i18n', lang + '.sh'), encoding='utf-8').read()))


def run_bash(script, env=None, timeout=30):
    e = os.environ.copy()
    e.update(env or {})
    r = subprocess.run([BASH, '-c', script], capture_output=True, text=True, env=e, timeout=timeout)
    return r.returncode, r.stdout.strip(), r.stderr.strip()


class PackConsistency(unittest.TestCase):
    def test_keys_identical(self):
        zh, en = pack('zh_CN'), pack('en')
        self.assertTrue(zh and en, '语言包缺失')
        self.assertEqual(sorted(zh), sorted(en), 'en.sh 与 zh_CN.sh 的键集合必须完全一致')

    def test_specifiers_match(self):
        zh, en = pack('zh_CN'), pack('en')
        bad = [k for k in zh if i18n_audit.SPEC_RE.findall(zh[k]) != i18n_audit.SPEC_RE.findall(en[k])]
        self.assertEqual(bad, [], '占位符不一致: %s' % bad[:5])

    def test_no_empty_values(self):
        for lang in ('zh_CN', 'en'):
            bad = [k for k, v in pack(lang).items() if not v.strip()]
            self.assertEqual(bad, [], '%s 有空值: %s' % (lang, bad[:5]))

    def test_english_pack_has_no_chinese(self):
        bad = [(k, v) for k, v in pack('en').items()
               if i18n_audit.CJK_RE.search(v) and k not in i18n_audit.EN_CJK_ALLOW]
        self.assertEqual(bad, [], 'en.sh 含中文: %s' % bad[:3])

    def test_every_english_key_is_real_english_text(self):
        # 兜底：英文值不能等于中文值（漏译会以「原样复制」的形式出现）
        zh, en = pack('zh_CN'), pack('en')
        same = [k for k in zh if i18n_audit.CJK_RE.search(zh[k]) and zh[k] == en[k]]
        self.assertEqual(same, [], '以下键英文未翻译: %s' % same[:5])


@needs_bash
class LookupBehaviour(unittest.TestCase):
    def _src(self, body, lang='en_US.UTF-8'):
        q = os.path.join(ROOT, 'src', 'lib', 'i18n.sh')
        return run_bash('FUSION_SRC="%s" . "%s"; %s' % (os.path.join(ROOT, 'src'), q, body),
                        env={'LANG': lang})

    def test_english_lookup(self):
        rc, out, _ = self._src('_i18n_init; L MSG_MAIN_0049', 'en_US.UTF-8')
        self.assertEqual((rc, out), (0, 'FusionBox help'))

    def test_chinese_lookup(self):
        rc, out, _ = self._src('_i18n_init; L MSG_MAIN_0049', 'zh_CN.UTF-8')
        self.assertEqual((rc, out), (0, 'FusionBox 帮助'))

    def test_printf_interpolation(self):
        rc, out, _ = self._src('_i18n_init; L MSG_MAIN_0002 "1.41.0"', 'en_US.UTF-8')
        self.assertEqual((rc, out), (0, 'Version: 1.41.0'))

    def test_unknown_key_returns_key_and_records_miss(self):
        rc, out, _ = self._src('_i18n_init; L MSG_DOES_NOT_EXIST; echo "misses=${#_I18N_MISSES[@]}"')
        self.assertIn('MSG_DOES_NOT_EXIST', out)
        self.assertIn('misses=1', out)

    def test_missing_en_key_falls_back_to_chinese(self):
        with tempfile.TemporaryDirectory() as d:
            io.open(os.path.join(d, 'zh_CN.sh'), 'w', encoding='utf-8').write('MSG_T_ONLY_ZH="仅中文"\n')
            io.open(os.path.join(d, 'en.sh'), 'w', encoding='utf-8').write('MSG_T_OTHER="other"\n')
            script = ('FUSION_SRC="%s" . "%s/src/lib/i18n.sh"; FUSION_I18N_DIR="%s"; '
                      '_load_lang en; L MSG_T_ONLY_ZH' % (os.path.join(ROOT, 'src'), ROOT, d))
            rc, out, _ = run_bash(script, env={'LANG': 'en_US.UTF-8'})
            self.assertEqual(out, '仅中文', '英文包缺键时必须回落中文而不是打印键名')

    def test_legacy_helpers_still_work(self):
        rc, out, _ = self._src('_i18n_init; _tr MSG_MAIN_0049 "回退值"; echo; _load_lang zh_CN; '
                               '_init_lang; echo "$F_LANG"', 'en_US.UTF-8')
        self.assertTrue(out.startswith('FusionBox help'), out)
        self.assertTrue(out.rstrip().endswith('zh_CN'), out)

    def test_no_key_is_unresolvable(self):
        # 英文模式下把所有键过一遍：不允许出现「返回值等于键名」（即查不到）。
        # 键列表经文件传入（3250 个键拼进命令行会超 Windows/部分系统的参数长度上限）；
        # 取值走 _i18n_get + $_I18N_VALUE 而不是命令替换，缺失登记才不会被子 shell 吞掉。
        keys = sorted(pack('en'))
        q = os.path.join(ROOT, 'src', 'lib', 'i18n.sh')
        with tempfile.NamedTemporaryFile('w', suffix='.keys', delete=False,
                                         encoding='utf-8', newline='\n') as fh:
            fh.write('\n'.join(keys) + '\n')
            key_file = fh.name
        try:
            script = ('FUSION_SRC="%s" . "%s"; _i18n_init; bad=0; '
                      'while IFS= read -r k; do [ -n "$k" ] || continue; '
                      '_i18n_get "$k"; [[ "$_I18N_VALUE" == "$k" ]] && { echo "unresolved=$k"; bad=1; }; '
                      'done < "%s"; '
                      'echo "misses=${#_I18N_MISSES[@]} bad=$bad"'
                      % (os.path.join(ROOT, 'src'), q, key_file))
            rc, out, _ = run_bash(script, env={'LANG': 'en_US.UTF-8'}, timeout=300)
        finally:
            os.unlink(key_file)
        self.assertIn('bad=0', out)
        self.assertIn('misses=0', out)


@needs_bash
class LanguageResolution(unittest.TestCase):
    def test_auto_follows_lang_env(self):
        q = os.path.join(ROOT, 'src', 'lib', 'i18n.sh')
        for lang, want in (('en_US.UTF-8', 'en'), ('zh_CN.UTF-8', 'zh_CN'), ('C', 'zh_CN'), ('', 'zh_CN')):
            rc, out, _ = run_bash('FUSION_SRC="%s" . "%s"; F_LANG=auto; _i18n_init; echo "$F_LANG"'
                                  % (os.path.join(ROOT, 'src'), q), env={'LANG': lang})
            self.assertEqual(out, want, 'LANG=%s 应解析为 %s' % (lang, want))

    def test_unknown_language_falls_back_to_chinese(self):
        q = os.path.join(ROOT, 'src', 'lib', 'i18n.sh')
        rc, out, _ = run_bash('FUSION_SRC="%s" . "%s"; F_LANG=klingon; _i18n_init; echo "$F_LANG"'
                              % (os.path.join(ROOT, 'src'), q))
        self.assertEqual(out, 'zh_CN')


@needs_bash
class CoverageAndWiring(unittest.TestCase):
    def test_core_layer_fully_extracted(self):
        rows, total = i18n_audit.count_untranslated(i18n_audit.CORE_FILES)
        self.assertEqual(total, 0, '核心层仍有未抽取文案: %s' % [r for r in rows if r[1]])

    def test_module_layer_fully_extracted(self):
        rows, total = i18n_audit.count_untranslated(i18n_audit.ALL_FILES)
        self.assertEqual(total, 0, '全仓仍有未抽取文案: %s' % [r for r in rows if r[1]])

    def test_install_embedded_table_matches_packs(self):
        problems = []
        i18n_audit.check_install_table(pack('zh_CN'), pack('en'), problems)
        self.assertEqual(problems, [])

    def test_lang_command_wired(self):
        fusion = io.open(os.path.join(ROOT, 'fusion.sh'), encoding='utf-8').read()
        common = io.open(os.path.join(ROOT, 'src', 'lib', 'common.sh'), encoding='utf-8').read()
        self.assertIn('lang|language)', fusion, 'route 未登记 lang 子命令')
        self.assertIn('lang_command', fusion)
        self.assertIn('lang_command()', common)
        # 只读的 status 允许非 root；写操作需要 root
        self.assertRegex(fusion, r'lang\|language\)\s*\n\s*\[\[ "\$\{2:-status\}" == status')

    def test_lang_unknown_argument_exit_code(self):
        q = os.path.join(ROOT, 'src', 'lib', 'common.sh')
        script = ('FUSION_SRC="%s" . "%s" >/dev/null 2>&1; lang_command bogus >/dev/null 2>&1; echo rc=$?'
                  % (os.path.join(ROOT, 'src'), q))
        rc, out, _ = run_bash(script, env={'LANG': 'en_US.UTF-8'})
        self.assertIn('rc=2', out)

    def test_pause_does_not_block_when_stdin_is_not_tty(self):
        q = os.path.join(ROOT, 'src', 'lib', 'common.sh')
        rc, out, err = run_bash('FUSION_SRC="%s" . "%s" >/dev/null 2>&1; pause; echo done'
                                % (os.path.join(ROOT, 'src'), q), timeout=10)
        self.assertEqual(rc, 0)
        self.assertIn('done', out, '非交互下 pause 必须立刻返回（否则只读命令会阻塞脚本）')

    def test_audit_script_passes(self):
        r = subprocess.run([sys.executable, os.path.join(ROOT, 'scripts', 'i18n_audit.py'), '--quiet'],
                           capture_output=True, text=True, timeout=60)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)


if __name__ == '__main__':
    unittest.main(verbosity=2)
