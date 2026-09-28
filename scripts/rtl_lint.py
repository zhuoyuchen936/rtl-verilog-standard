#!/usr/bin/env python3
"""rtl_lint.py -- one command to lint + synthesis-smoke-test Verilog/SystemVerilog.

Why this exists: every agent that touches RTL otherwise reinvents "how do I
actually check this compiles", and on Windows the usual answer (verilator) is
only reachable through WSL. This wraps both cases so the check is one command
everywhere, and turns the raw tool output into a rule-code summary you can act
on.

Two independent checks, because they catch different things:

  verilator --lint-only   syntax, width mismatches, incomplete sensitivity,
                          inferred latches, unused/undriven nets, case coverage
  yosys  proc; check      structural problems a linter cannot see: real latch
                          inference after proc, multi-driven nets, combinational
                          loops, and a gate/cell count sanity number

Usage
-----
  python rtl_lint.py rtl/*.v
  python rtl_lint.py --top counter --sv rtl/counter.sv
  python rtl_lint.py --top fifo --synth rtl/*.v      # add the yosys pass
  python rtl_lint.py --inc rtl/include --top top rtl/*.v

Exit status is non-zero if any error (or, with --strict, any warning) is found,
so it drops straight into a Makefile or CI step.
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
from collections import Counter

IS_WINDOWS = os.name == "nt"

# Homebrew installs into /opt/homebrew (Apple Silicon) or /usr/local (Intel), and
# neither is on PATH in a non-login shell -- which is exactly how this script gets
# invoked from CI, from Makefiles and from agent tooling. Without this fallback
# shutil.which() reports "verilator not found" on a Mac where verilator is
# installed and working, and the whole check silently degrades to nothing.
FALLBACK_BIN_DIRS = ("/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin")

# This script prints Chinese. On a default Windows console stdout is the ANSI
# codepage (cp936/cp1252), so those prints raise UnicodeEncodeError and the tool
# dies before it ever runs verilator. Force UTF-8 and degrade gracefully rather
# than crash -- a self-check script that crashes is worse than no script.
for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError):
        pass


# --------------------------------------------------------------------------
# Locating the tools. On Windows we fall back to WSL, which means paths handed
# to the tool have to be translated too -- keep those two facts together.
# --------------------------------------------------------------------------

class Runner:
    """Runs a tool either natively or inside WSL, translating paths as needed."""

    def __init__(self, tool: str, distro: str | None = None):
        self.tool = tool
        self.distro = distro
        self.native = shutil.which(tool) or self._search_fallback_dirs(tool)
        self.via_wsl = False
        if not self.native and IS_WINDOWS and shutil.which("wsl"):
            if self._wsl_has(tool):
                self.via_wsl = True

    def _wsl_base(self) -> list[str]:
        cmd = ["wsl"]
        if self.distro:
            cmd += ["-d", self.distro]
        return cmd + ["--"]

    def _wsl_has(self, tool: str) -> bool:
        try:
            r = subprocess.run(
                self._wsl_base() + ["bash", "-c", f"command -v {tool}"],
                capture_output=True, text=True, timeout=120,
            )
            return r.returncode == 0 and r.stdout.strip() != ""
        except Exception:
            return False

    @property
    def available(self) -> bool:
        return bool(self.native) or self.via_wsl

    @staticmethod
    def _search_fallback_dirs(tool: str) -> str | None:
        """Look in the well-known package-manager bindirs PATH may not carry."""
        for d in FALLBACK_BIN_DIRS:
            cand = os.path.join(d, tool)
            if os.path.isfile(cand) and os.access(cand, os.X_OK):
                return cand
        return None

    @staticmethod
    def to_wsl_path(p: str) -> str:
        ap = os.path.abspath(p)
        drive, rest = os.path.splitdrive(ap)
        if drive:
            return "/mnt/" + drive[0].lower() + rest.replace("\\", "/")
        return ap.replace("\\", "/")

    def path(self, p: str) -> str:
        return self.to_wsl_path(p) if self.via_wsl else p

    def run(self, argv: list[str]) -> subprocess.CompletedProcess:
        full = (self._wsl_base() + [self.tool] + argv) if self.via_wsl \
            else [self.native or self.tool] + argv
        return subprocess.run(full, capture_output=True, text=True)

    def describe(self) -> str:
        if self.native:
            return f"{self.tool} (native: {self.native})"
        if self.via_wsl:
            return f"{self.tool} (via WSL{'/' + self.distro if self.distro else ''})"
        return f"{self.tool} (NOT FOUND)"


# --------------------------------------------------------------------------
# Verilator
# --------------------------------------------------------------------------

# Verilator prefixes each diagnostic with %Error / %Warning-CODE.
VERILATOR_MSG = re.compile(r"^%(Error|Warning)(?:-([A-Z0-9_]+))?:", re.M)

# Warnings worth explaining, because the message alone rarely tells a newcomer
# what to actually change.
HINTS = {
    "WIDTH": "位宽不匹配：显式写出位宽或用 {N{1'b0}} 扩展，别指望隐式截断",
    "WIDTHEXPAND": "右值比左值窄；按表达式的 signedness 做零/符号扩展，确认扩展符合意图",
    "WIDTHTRUNC": "右值比左值宽，高位会被丢弃——这是最常见的静默 bug",
    "LATCH": "推断出了锁存器：组合 always 块里有路径没赋值，补 default 或先赋默认值",
    "CASEINCOMPLETE": "case 未覆盖所有取值；检查默认赋值与保持意图，不一定会推断锁存器",
    "CASEX": "casex/casez 会把 x/z 当通配，综合前仿真易掩盖 bug，改用 case 或 casez+明确编码",
    "COMBDLY": "组合块里用了非阻塞赋值 <=：组合逻辑应当用阻塞赋值 =",
    "BLKSEQ": "时序块里用了阻塞赋值 =：时序逻辑应当用非阻塞赋值 <=",
    "MULTIDRIVEN": "同一信号被多个 always 块驱动：综合会失败或产生意外结果",
    "UNOPTFLAT": "疑似组合环路（或需要拆分的自反馈信号）",
    "IMPLICIT": "隐式声明的线网：加 `default_nettype none` 可以把这类拼写错误变成编译错误",
    "PINMISSING": "例化时有端口没连接",
    "PINCONNECTEMPTY": "例化时端口显式接空",
    "DECLFILENAME": "文件名与模块名不一致（本规范要求一致）",
    "UNUSEDSIGNAL": "信号声明了但没用到",
    "UNDRIVEN": "信号被读取但没有任何驱动",
    "SYNCASYNCNET": "同一信号同时用作同步和异步复位",
}


def run_verilator(runner: Runner, files, top, sv, incdirs, defines, extra, waivers,
                  v2001=False):
    argv = ["--lint-only", "-Wall"]
    if v2001:
        # Verilator parses as SystemVerilog by DEFAULT, so a .v file full of
        # always_comb/logic/enum lints perfectly clean. If the project baseline
        # is Verilog-2001, that has to be stated explicitly or the baseline is
        # unenforced -- this flag is what actually makes SV syntax an error.
        argv += ["--language", "1364-2001"]
    elif sv:
        argv.append("-sv")
    if top:
        argv += ["--top-module", top]
    for d in incdirs:
        argv.append("-I" + runner.path(d))
    for d in defines:
        argv.append("+define+" + d)
    # Waiver (.vlt) files are paths, so they need the same WSL translation the
    # sources get, and verilator requires them ahead of the sources.
    for w in waivers:
        argv.append(runner.path(w))
    argv += extra
    argv += [runner.path(f) for f in files]
    return runner.run(argv)


def summarize_verilator(out: str):
    codes = Counter()
    for m in VERILATOR_MSG.finditer(out):
        kind, code = m.group(1), m.group(2)
        codes[code or kind.upper()] += 1
    errors = sum(1 for m in VERILATOR_MSG.finditer(out) if m.group(1) == "Error")
    warnings = sum(1 for m in VERILATOR_MSG.finditer(out) if m.group(1) == "Warning")
    return codes, errors, warnings


# --------------------------------------------------------------------------
# Yosys structural check
# --------------------------------------------------------------------------

def tcl_quote(value: str) -> str:
    """Quote a Tcl word without variable, command or backslash substitution."""
    if any(c in value for c in '\r\n\x00'):
        raise ValueError("Yosys arguments cannot contain newlines or NUL")
    return '"' + ''.join('\\' + c if c in '\\"$[]' else c for c in value) + '"'


def run_yosys(runner: Runner, files, top, sv, incdirs=(), defines=()):
    # The .ys command parser preserves quotes in -I/-D values. Use the Tcl
    # bridge's argument-vector form so spaces/macros arrive unchanged.
    read_args = ["read_verilog"] + (["-sv"] if sv else [])
    for directory in incdirs:
        read_args += ["-I", runner.path(os.path.abspath(directory))]
    for define in defines:
        read_args += ["-D", define]
    read_args += [runner.path(os.path.abspath(f)) for f in files]
    cmds = ["yosys " + " ".join(tcl_quote(arg) for arg in read_args)]
    cmds.append("yosys hierarchy -check" + (" -top " + tcl_quote(top) if top else " -auto-top"))
    # Assert on actual cell types before optimization can discard a latch.
    cmds += ["yosys proc",
             'yosys select -assert-none {t:$dlatch} {t:$adlatch} {t:$dlatchsr}',
             "yosys opt -purge", "yosys check -assert", "yosys stat"]
    with tempfile.TemporaryDirectory(prefix="rtl-yosys-") as tmp:
        script = os.path.join(tmp, "check.tcl")
        with open(script, "w", encoding="utf-8") as stream:
            stream.write("\n".join(cmds) + "\n")
        return runner.run(["-c", runner.path(script)])


def main() -> int:
    ap = argparse.ArgumentParser(
        description="Lint and synthesis-smoke-test Verilog/SystemVerilog.")
    ap.add_argument("files", nargs="+", help="RTL source files")
    ap.add_argument("--top", help="top module name")
    language = ap.add_mutually_exclusive_group()
    language.add_argument("--sv", action="store_true", help="treat sources as SystemVerilog")
    language.add_argument("--v2001", action="store_true",
                    help="enforce the Verilog-2001 baseline (--language 1364-2001). "
                         "Without this, verilator parses as SystemVerilog and SV syntax "
                         "in a .v file lints clean.")
    ap.add_argument("--inc", action="append", default=[], help="include directory (repeatable)")
    ap.add_argument("--define", action="append", default=[], help="+define+NAME[=VAL] (repeatable)")
    ap.add_argument("--synth", action="store_true", help="also run the yosys structural check")
    ap.add_argument("--strict", action="store_true", help="exit non-zero on warnings too")
    ap.add_argument("--distro", help="WSL distro to use (Windows only; ignored on macOS/Linux)")
    ap.add_argument("--waiver", action="append", default=[],
                    help="verilator .vlt waiver file (repeatable); path is WSL-translated")
    ap.add_argument("--verilator-arg", action="append", default=[],
                    help="extra raw flag passed to verilator, e.g. --verilator-arg=--timing "
                         "(use = form; a bare flag would be parsed as this script's own option)")
    args = ap.parse_args()

    if args.top and not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_$]*", args.top):
        ap.error("--top must be a simple Verilog module identifier")
    if any(any(c in s for c in '\r\n\x00') for s in
           args.files + args.waiver + args.inc + args.define):
        ap.error("paths and defines cannot contain newlines or NUL")
    missing = [f for f in args.files + args.waiver if not os.path.isfile(f)]
    missing += [d for d in args.inc if not os.path.isdir(d)]
    if missing:
        print("找不到这些文件: " + ", ".join(missing), file=sys.stderr)
        return 2

    vl = Runner("verilator", args.distro)
    print("=" * 72)
    print("工具: " + vl.describe())

    if not vl.available:
        print("\n找不到 verilator。安装方式：", file=sys.stderr)
        print("  Ubuntu/WSL : sudo apt install verilator", file=sys.stderr)
        print("  macOS      : brew install verilator", file=sys.stderr)
        return 2

    rc_total = 0

    r = run_verilator(vl, args.files, args.top, args.sv, args.inc,
                      args.define, args.verilator_arg, args.waiver, args.v2001)
    out = (r.stdout or "") + (r.stderr or "")
    codes, errors, warnings = summarize_verilator(out)

    print("=" * 72)
    print(f"[verilator --lint-only -Wall]  错误 {errors} / 警告 {warnings}")
    print("=" * 72)
    if out.strip():
        print(out.rstrip())
    if codes:
        print("-" * 72)
        print("按规则代码汇总：")
        for code, n in codes.most_common():
            hint = HINTS.get(code, "")
            print(f"  {code:<18} x{n:<4} {hint}")
    if r.returncode == 0 and errors == 0 and warnings == 0:
        print("  lint 干净 ✔")
    if r.returncode != 0:
        print(f"  Verilator 返回码: {r.returncode}")

    if r.returncode != 0 or errors or (args.strict and warnings):
        rc_total = 1

    synth_ran = False
    if args.synth:
        ys = Runner("yosys", args.distro)
        print()
        print("=" * 72)
        print("工具: " + ys.describe())
        if not ys.available:
            # Silently skipping here and still printing "通过 ✔" would be the worst
            # possible failure mode: the structural pass is exactly what catches
            # real latches, multi-driven nets and combinational loops, and a linter
            # cannot see them. A gate that can quietly half-disable itself is not a
            # gate, so this is an explicit failure.
            print("!! 找不到 yosys，**结构检查未执行**（安装：sudo apt install yosys）")
            print("!! 你要求了 --synth，但只跑了 verilator 那一半——真 latch / 多驱动 / 组合环没有被检查。")
            synth_ran = False
            rc_total = 1
        else:
            synth_ran = True
            ry = run_yosys(ys, args.files, args.top, args.sv, args.inc, args.define)
            yout = (ry.stdout or "") + (ry.stderr or "")
            print("=" * 72)
            print(f"[yosys hierarchy/proc/check]  返回码 {ry.returncode}")
            print("=" * 72)
            # The full yosys log is long and mostly noise; keep the parts that
            # signal a real structural problem plus the final cell statistics.
            keep, in_stat = [], False
            for line in yout.splitlines():
                if line.startswith("=== ") or line.strip().startswith("Number of"):
                    in_stat = True
                if in_stat or re.search(
                        r"Warning|ERROR|latch|multiple drivers|combinational loop",
                        line, re.I):
                    keep.append(line)
            print("\n".join(keep[-80:]) if keep else yout[-2000:])
            if ry.returncode != 0:
                rc_total = 1

    print()
    print("=" * 72)
    # Always say which halves actually ran, so "通过 ✔" can never be read as more
    # coverage than was really obtained.
    scope = "verilator lint" + (" + yosys 结构检查" if synth_ran else " （未跑结构检查）")
    print("检查范围: " + scope)
    if not args.synth:
        print("提示: 没有加 --synth；本次结果只覆盖 Verilator lint。")
    print("结论: " + ("通过 ✔" if rc_total == 0 else "有问题，见上面的输出 ✘"))
    return rc_total


if __name__ == "__main__":
    sys.exit(main())
