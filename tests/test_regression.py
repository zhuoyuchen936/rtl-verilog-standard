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

    def check_protocol(self, design, bench, cases, old, new):
        """Run the shipped RTL, then a compilable single-fault copy against the same TB."""
        iverilog, vvp = self.require('iverilog', 'vvp')
        source = ROOT / 'assets/templates/v2001' / f'{design}.v'
        tb = ROOT / 'tests/hdl' / f'tb_{bench}.sv'
        with tempfile.TemporaryDirectory(prefix='rtl-protocol-') as tmp:
            folder = Path(tmp)
            content = source.read_text()
            self.assertEqual(content.count(old), 1, f'fault site in {source.name}')
            broken = folder / source.name
            broken.write_text(content.replace(old, new))
            for candidate, params in [(source, case) for case in cases] + [(broken, cases[0])]:
                with self.subTest(design=design, params=params, injected=candidate == broken):
                    overrides = [f'-Ptb_{bench}.{k}={v}' for k, v in params.items()]
                    build = run([iverilog, '-g2012', '-s', f'tb_{bench}', *overrides,
                                 '-o', 'sim', candidate, tb], folder)
                    self.assertEqual(build.returncode, 0, build.stdout)
                    sim = run([vvp, '-N', 'sim'], folder)
                    if candidate == broken:
                        self.assertNotEqual(sim.returncode, 0, sim.stdout)
                        self.assertIn('FATAL:', sim.stdout)
                        self.assertNotIn('timeout', sim.stdout.lower())
                    else:
                        self.assertEqual(sim.returncode, 0, sim.stdout)
                        self.assertIn(f'PASS {bench} ', sim.stdout)

    def test_single_stage_ready_valid(self):
        self.check_protocol('module_skeleton', 'ready_valid', [{'CAPACITY': 1}],
                            'else if (in_ready)', "else if (1'b1)")

    def test_skid_buffer_ready_valid(self):
        self.check_protocol('skid_buffer', 'ready_valid', [{'CAPACITY': 2}],
                            'skid_data  <= s_data;', 'skid_data  <= ~s_data;')

    def test_async_fifo_order_wrap_and_reset(self):
        self.check_protocol('async_fifo', 'async_fifo', [
            {'ASIZE': 2, 'W_HALF': 3, 'R_HALF': 7, 'PHASE': 1},
            {'ASIZE': 3, 'W_HALF': 7, 'R_HALF': 3, 'PHASE': 3},
            {'ASIZE': 2, 'W_HALF': 5, 'R_HALF': 5, 'PHASE': 1}],
            '(rd_en & ~rd_empty)', 'rd_en')

    def test_mcp_exactly_once(self):
        self.check_protocol('handshake_mcp', 'handshake_mcp', [
            {'S_HALF': 3, 'D_HALF': 7}, {'S_HALF': 7, 'D_HALF': 3}],
            'dst_valid <= req_edge;', 'dst_valid <= req_edge | dst_valid;')

    def test_open_loop_pulse_contract(self):
        self.check_protocol('pulse_sync', 'pulse_sync', [{}],
                            'sync2 ^ sync3', 'sync2 & ~sync3')

    def test_ram_read_first_and_hold(self):
        self.check_protocol('sdp_ram', 'sdp_ram', [{}],
                            '<= mem[raddr];', '<= (we && waddr == raddr) ? wdata : mem[raddr];')

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

    def test_conflicting_constant_driver_is_rejected_before_optimization(self):
        self.require('verilator', 'yosys')
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / 'conflict.v'
            source.write_text('''module conflict(input wire clk, input wire d, output reg q);
always @(posedge clk) q <= d;
always @(posedge clk) q <= 1'b0;
endmodule
''')
            result = self.cli('--v2001', '--strict', '--synth', '--top', 'conflict', source)
            self.assertNotEqual(result.returncode, 0, result.stdout)
            self.assertIn('multiple conflicting drivers', result.stdout.lower())

    def test_make_uses_current_rtl_header_and_filelist(self):
        self.require('make', 'verilator', 'yosys', 'iverilog', 'vvp')
        makefile = ROOT / 'assets/templates/Makefile'
        with tempfile.TemporaryDirectory(prefix='rtl make ') as tmp:
            folder = Path(tmp)
            inc = folder / 'rtl/inc'
            inc.mkdir(parents=True)
            (folder / 'tb').mkdir()
            header = inc / 'mask.vh'
            source = folder / 'rtl/soc_top.v'
            filelist = folder / 'rtl/rtl.f'
            header.write_text("`define MASK 1'b0\n")
            source.write_text('''`include "mask.vh"
module soc_top(input wire d, output wire q);
assign q = d ^ `MASK ^ `FEATURE;
endmodule
''')
            filelist.write_text("+incdir+rtl/inc\n+define+FEATURE=1'b0\nrtl/soc_top.v\n")
            (folder / 'tb/tb_soc_top.v').write_text('''module tb_soc_top;
reg d;
wire q;
soc_top dut(.d(d), .q(q));
initial begin
    d = 1'b1;
    #1;
    if (q !== d) begin $display("wrong output"); $stop; end
    $display("matched");
    $finish;
end
endmodule
''')
            make = ['make', '-f', makefile, 'RTL_LANG=v2001', f'RTL_LINT={SCRIPT}',
                    f'PYTHON={sys.executable}']
            for target in ('lint', 'sim'):
                result = run([*make, target], folder)
                self.assertEqual(result.returncode, 0, result.stdout)
            for path, old, new in ((source, 'q = d', 'q = ~d'), (header, "1'b0", "1'b1"),
                                   (filelist, "1'b0", "1'b1")):
                with self.subTest(changed=path.name):
                    original = path.read_text()
                    path.write_text(original.replace(old, new))
                    result = run([*make, 'sim'], folder)
                    self.assertNotEqual(result.returncode, 0, result.stdout)
                    self.assertIn('wrong output', result.stdout)
                    path.write_text(original)
                    restored = run([*make, 'sim'], folder)
                    self.assertEqual(restored.returncode, 0, restored.stdout)
                    self.assertIn('matched', restored.stdout)

            # Bare macro used as a numeric one, Windows BOM/CRLF, no final newline.
            source.write_text(source.read_text().replace('q = d', 'q = ~d'))
            filelist.write_bytes(b'\xef\xbb\xbf+incdir+rtl/inc\r\n+define+FEATURE\r\nrtl/soc_top.v')
            for target in ('lint', 'sim'):
                result = run([*make, target], folder)
                self.assertEqual(result.returncode, 0, result.stdout)
            filelist.write_text('-f missing.f\n')
            rejected = run([*make, 'sim'], folder)
            self.assertNotEqual(rejected.returncode, 0, rejected.stdout)
            self.assertIn('unsupported filelist entry', rejected.stdout)

    def test_filelist_rejects_unhandled_options(self):
        with tempfile.TemporaryDirectory() as tmp:
            filelist = Path(tmp) / 'rtl.f'
            for entry in ('-f child.f', '+libext+.v', '+incdir+a+b', '+define+', '`define A'):
                with self.subTest(entry=entry):
                    filelist.write_text(f'{entry}\nexample.v\n')
                    result = self.cli('--v2001', '--filelist', filelist)
                    self.assertEqual(result.returncode, 2, result.stdout)
                    self.assertIn(f'{filelist}:1:', result.stdout)

    def test_documented_division_example_matches_integer_reference(self):
        iverilog, vvp = self.require('iverilog', 'vvp')
        reference = (ROOT / 'references/07-datapath-and-width.md').read_text()
        section = reference.split('### R-07-08 ', 1)[1].split('\n### ', 1)[0]
        snippet = section.split('```verilog\n', 1)[1].split('\n```', 1)[0]
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            bench = folder / 'tb.v'
            bench.write_text('module tb;\nreg signed [7:0] a;\nreg [7:0] u;\n' + snippet + '''
integer n, unsigned_n, ref_q, ref_r;
initial begin
    for (n = -128; n <= 127; n = n + 1) begin
        a = n[7:0];
        u = n[7:0];
        unsigned_n = (n < 0) ? n + 256 : n;
        ref_q = (n < 0) ? -((-n) / 8) : n / 8;
        ref_r = n - (ref_q * 8);
        #1;
        if (quotient !== ref_q || remainder !== ref_r ||
            unsigned_q !== unsigned_n / 8 || unsigned_r !== unsigned_n % 8) begin
            $display("mismatch for a=%0d", n);
            $stop;
        end
    end
    $display("256 inputs matched");
    $finish;
end
endmodule
''')
            build = run([iverilog, '-g2001', '-s', 'tb', '-o', 'sim', bench], folder)
            self.assertEqual(build.returncode, 0, build.stdout)
            result = run([vvp, '-N', 'sim'], folder)
            self.assertEqual(result.returncode, 0, result.stdout)
            self.assertIn('256 inputs matched', result.stdout)

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
