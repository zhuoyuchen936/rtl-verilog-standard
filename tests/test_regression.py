"""Regression checks for exit status, build configuration and shipped templates.

Run from the skill root: python3 -m unittest discover -s tests -v
Real EDA tests skip explicitly if tools are unavailable; no tools are installed.
All generated HDL and simulator output stay in temporary directories.
"""
import contextlib
import importlib.util
import io
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'scripts/rtl_lint.py'
spec = importlib.util.spec_from_file_location('rtl_lint', SCRIPT)
lint = importlib.util.module_from_spec(spec)
spec.loader.exec_module(lint)


def run(argv, cwd=None):
    return subprocess.run([str(x) for x in argv], cwd=cwd, text=True,
                          stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60)


class ExitStatusTests(unittest.TestCase):
    def invoke(self, rc, output, *args, unavailable=()):
        class FakeRunner:
            def __init__(self, tool, distro=None):
                self.tool = tool
                self.available = tool not in unavailable
            def describe(self):
                return self.tool
            def path(self, value):
                return value
            def run(self, argv):
                return subprocess.CompletedProcess(argv, rc, output, '')
        with patch.object(lint, 'Runner', FakeRunner), patch.object(
                sys, 'argv', [str(SCRIPT), str(ROOT / 'assets/templates/v2001/fsm_3seg.v'), *args]), \
                contextlib.redirect_stdout(io.StringIO()) as out, \
                contextlib.redirect_stderr(io.StringIO()):
            status = lint.main()
        return status, out.getvalue()

    def test_crash_without_diagnostic_is_failure(self):
        rc, out = self.invoke(-11, 'unexpected termination')
        self.assertNotEqual(rc, 0)
        self.assertNotIn('lint 干净', out)
        self.assertNotIn('通过 ✔', out)

    def test_warning_policy_and_process_status(self):
        warning = '%Warning-WIDTH: mismatch\n'
        self.assertEqual(self.invoke(0, warning)[0], 0)
        self.assertNotEqual(self.invoke(0, warning, '--strict')[0], 0)
        self.assertNotEqual(self.invoke(1, warning)[0], 0)

    def test_requested_missing_synth_is_failure(self):
        self.assertNotEqual(self.invoke(0, '', '--synth', unavailable=('yosys',))[0], 0)

    def test_missing_linter_is_failure(self):
        self.assertEqual(self.invoke(0, '', unavailable=('verilator',))[0], 2)


class RealToolTests(unittest.TestCase):
    def require(self, *names):
        paths = []
        for name in names:
            runner = lint.Runner(name)
            if not runner.native:
                self.skipTest(f'{name} native executable unavailable')
            paths.append(runner.native)
        return paths

    def cli(self, *args):
        return run([sys.executable, SCRIPT, *args], ROOT)

    def test_templates_lint_and_structure(self):
        self.require('verilator', 'yosys')
        sources = sorted((ROOT / 'assets/templates').rglob('*'))
        for source in sources:
            if source.suffix not in ('.v', '.sv') or source.name.startswith('tb_'):
                continue
            with self.subTest(template=source.name):
                result = self.cli('--sv' if source.suffix == '.sv' else '--v2001',
                                  '--top', source.stem, '--strict', '--synth', source)
                self.assertEqual(result.returncode, 0, result.stdout)

    def test_include_define_and_space_paths_reach_both_tools(self):
        self.require('verilator', 'yosys')
        with tempfile.TemporaryDirectory(prefix='rtl space ; ') as tmp:
            folder = Path(tmp)
            inc = folder / 'include files'
            inc.mkdir()
            (inc / 'width.vh').write_text('`define WIDTH 8\n')
            source = folder / 'configured.v'
            source.write_text('''`include "width.vh"
module configured(input wire [`WIDTH-1:0] a, output wire [`WIDTH-1:0] y);
    assign y = a ^ `MASK;
endmodule
''')
            result = self.cli('--v2001', '--synth', '--strict', '--top', 'configured',
                              '--inc', inc, '--define', "MASK=8'hA5", source)
            self.assertEqual(result.returncode, 0, result.stdout)

    def test_yosys_rejects_latch_even_when_verilator_waives_it(self):
        self.require('verilator', 'yosys')
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / 'bad.v'
            source.write_text('''module bad(input wire en, input wire d, output reg q);
/* verilator lint_off LATCH */
always @(*) if (en) q = d;
/* verilator lint_on LATCH */
endmodule
''')
            lint_only = self.cli('--v2001', '--strict', '--top', 'bad', source)
            self.assertEqual(lint_only.returncode, 0, lint_only.stdout)
            synthesis = self.cli('--v2001', '--strict', '--synth', '--top', 'bad', source)
            self.assertNotEqual(synthesis.returncode, 0, synthesis.stdout)
            self.assertIn('Assertion failed', synthesis.stdout)

    def test_filename_dlatch_does_not_fake_a_latch(self):
        self.require('verilator', 'yosys')
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / 'dlatch.v'
            source.write_text('module dlatch(input wire d, output wire q); assign q = d; endmodule\n')
            result = self.cli('--v2001', '--synth', '--strict', '--top', 'dlatch', source)
            self.assertEqual(result.returncode, 0, result.stdout)

    def test_language_validation(self):
        self.require('verilator')
        source = ROOT / 'assets/templates/sv/fsm_3seg_sv.sv'
        self.assertNotEqual(self.cli('--v2001', source).returncode, 0)
        self.assertEqual(self.cli('--v2001', '--sv', source).returncode, 2)

    def test_icarus_tb_success_failure_and_timeout(self):
        iverilog, vvp = self.require('iverilog', 'vvp')
        original = (ROOT / 'assets/templates/v2001/tb_fsm_3seg.v').read_text()
        variants = {
            'success': original,
            'failure': original.replace('integer errors = 0;', 'integer errors = 1;'),
            'timeout': original.replace('TIMEOUT_NS = 10_000;', 'TIMEOUT_NS = 1;'),
        }
        with tempfile.TemporaryDirectory() as tmp:
            for mode, content in variants.items():
                with self.subTest(mode=mode):
                    source = Path(tmp) / 'tb_fsm_3seg.v'
                    source.write_text(content)
                    binary = Path(tmp) / 'sim.vvp'
                    compiled = run([iverilog, '-g2001', '-s', 'tb_fsm_3seg', '-o', binary,
                                    source, ROOT / 'assets/templates/v2001/fsm_3seg.v'], tmp)
                    self.assertEqual(compiled.returncode, 0, compiled.stdout)
                    simulated = run([vvp, '-N', binary], tmp)
                    self.assertEqual(simulated.returncode == 0, mode == 'success', simulated.stdout)
                    self.assertIn('TEST PASSED' if mode == 'success' else 'TEST FAILED', simulated.stdout)
            self.assertFalse(list(Path(tmp).glob('*.vcd')))

    def test_verilator_tb_success_failure_and_timeout(self):
        verilator, = self.require('verilator')
        self.require('make', 'c++')
        original = (ROOT / 'assets/templates/v2001/tb_fsm_3seg.v').read_text()
        variants = {
            'success': original,
            'failure': original.replace('integer errors = 0;', 'integer errors = 1;'),
            'timeout': original.replace('TIMEOUT_NS = 10_000;', 'TIMEOUT_NS = 1;'),
        }
        with tempfile.TemporaryDirectory() as tmp:
            for mode, content in variants.items():
                with self.subTest(mode=mode):
                    source = Path(tmp) / 'tb_fsm_3seg.v'
                    source.write_text(content)
                    build = Path(tmp) / mode
                    compiled = run([verilator, '--binary', '--timing', '-Wall',
                                    '--language', '1364-2001', '--timescale', '1ns/1ps',
                                    '--top-module', 'tb_fsm_3seg', '--Mdir', build,
                                    source, ROOT / 'assets/templates/v2001/fsm_3seg.v'], tmp)
                    self.assertEqual(compiled.returncode, 0, compiled.stdout)
                    simulated = run([build / 'Vtb_fsm_3seg'], tmp)
                    self.assertEqual(simulated.returncode == 0, mode == 'success', simulated.stdout)
                    self.assertIn('TEST PASSED' if mode == 'success' else 'TEST FAILED', simulated.stdout)


if __name__ == '__main__':
    unittest.main()
