# ============================================================================
# BRANCH_PREDICTOR - top-level Makefile
# ============================================================================

TB_DIR := sim/tb

.PHONY: all compile run verdi verdi_sch clean rerun help \
        core core_rerun core_verdi \
        single single_rerun single_verdi \
        overlap overlap_rerun overlap_verdi \
        trace trace_rerun trace_verdi trace_sweep gen_trace \
        mermaid tree

all:
	$(MAKE) -C $(TB_DIR) all

compile:
	$(MAKE) -C $(TB_DIR) compile

run:
	$(MAKE) -C $(TB_DIR) run

verdi:
	$(MAKE) -C $(TB_DIR) verdi

verdi_sch:
	$(MAKE) -C $(TB_DIR) verdi_sch

clean:
	$(MAKE) -C $(TB_DIR) clean

rerun:
	$(MAKE) -C $(TB_DIR) rerun

core:
	$(MAKE) -C $(TB_DIR) core

core_rerun:
	$(MAKE) -C $(TB_DIR) core_rerun

core_verdi:
	$(MAKE) -C $(TB_DIR) core_verdi

single:
	$(MAKE) -C $(TB_DIR) single

single_rerun:
	$(MAKE) -C $(TB_DIR) single_rerun

single_verdi:
	$(MAKE) -C $(TB_DIR) single_verdi

overlap:
	$(MAKE) -C $(TB_DIR) overlap

overlap_rerun:
	$(MAKE) -C $(TB_DIR) overlap_rerun

overlap_verdi:
	$(MAKE) -C $(TB_DIR) overlap_verdi

gen_trace:
	$(MAKE) -C $(TB_DIR) gen_trace

trace:
	$(MAKE) -C $(TB_DIR) trace

trace_rerun:
	$(MAKE) -C $(TB_DIR) trace_rerun

trace_verdi:
	$(MAKE) -C $(TB_DIR) trace_verdi

trace_sweep:
	$(MAKE) -C $(TB_DIR) trace_sweep

mermaid:
	$(MAKE) -C $(TB_DIR) mermaid

help:
	$(MAKE) -C $(TB_DIR) help

tree:
	@find . -path './.git' -prune -o -path './.agents' -prune -o -print
