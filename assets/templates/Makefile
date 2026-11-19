# Run from the project root. All paths in RTL_F use that directory as their base.
TOP       ?= soc_top
TB_TOP    ?= tb_soc_top
RTL_F     ?= rtl/rtl.f
TB_SRCS   ?= $(wildcard tb/*.v tb/*.sv)
RTL_LANG  ?= sv
RTL_LINT  ?= scripts/rtl_lint.py
PYTHON    ?= python3
WAIVER    ?= $(wildcard lint/waivers.vlt)
BUILD     ?= build
WAVE      ?= gtkwave
WAVEFILE  ?= $(BUILD)/sim/wave.fst

ifeq ($(RTL_LANG),sv)
IVLANG = -g2012
else ifeq ($(RTL_LANG),v2001)
IVLANG = -g2001
else
$(error RTL_LANG must be sv or v2001)
endif

.PHONY: lint sim wave smoke syn clean FORCE
lint:
	$(PYTHON) "$(RTL_LINT)" --$(RTL_LANG) --top "$(TOP)" --synth --strict \
	    $(if $(WAIVER),--waiver "$(WAIVER)") --filelist "$(RTL_F)"

# This small standalone example always compiles the current sources and options.
$(BUILD)/sim.vvp: FORCE
	@mkdir -p "$(BUILD)/sim"
	@set -e; manifest=$$(mktemp "$(BUILD)/sim/rtl.XXXXXX"); \
	    trap 'rm -f "$$manifest"' 0; \
	    $(PYTHON) "$(RTL_LINT)" --emit-iverilog-filelist "$(RTL_F)" > "$$manifest"; \
	    iverilog $(IVLANG) -Wall -Winfloop -s "$(TB_TOP)" -o "$@" -c "$$manifest" $(TB_SRCS)

sim: $(BUILD)/sim.vvp
	vvp -N "$<" -fst

wave: $(BUILD)/sim.vvp
	vvp -N "$<" -fst +trace && $(WAVE) "$(WAVEFILE)"

smoke:
	@mkdir -p "$(BUILD)/syn"
	yosys -s syn/smoke.ys -l "$(BUILD)/yosys.log"

syn:
	@mkdir -p "$(BUILD)"
	vivado -mode batch -source syn/build.tcl -log "$(BUILD)/vivado.log" -journal "$(BUILD)/vivado.jou"

clean:
	$(RM) "$(BUILD)/sim.vvp" "$(WAVEFILE)"
