# ============================================================================
# BRANCH_PREDICTOR - simulation Makefile
# ============================================================================

PROJ_ROOT := ../..

FLIST     ?= core.f
FSDB_NAME ?= tb_tage_predictor_core.fsdb

FLIST_PATH = sim/tb/$(FLIST)
SIM_ROOT   = sim
RUN_NAME   ?= 01
RUN_DIR    = $(SIM_ROOT)/$(RUN_NAME)
FSDB_FILE  = $(RUN_DIR)/$(FSDB_NAME)
SIMV       = $(RUN_DIR)/simv
VCS_MDIR   = $(RUN_DIR)/csrc
VERDI_FLIST = $(RUN_DIR)/verdi_$(FLIST)

MAX_CYCLES ?= 50000

TRACE_WORKSET    ?= 128
TRACE_BRANCHES   ?= 100000
TRACE_PATTERN    ?= mixed
TRACE_WARMUP     ?= 10000
TRACE_BODY_LEN   ?= -1
TRACE_BODY_LEN_MIN ?= 0
TRACE_BODY_LEN_MAX ?= 15
TRACE_DEEP_LEN   ?= 0
TRACE_DEEP_PERIOD ?= 2048
TRACE_DEEP_START ?= 0
TRACE_SEED       ?= 1
TRACE_CFG        ?= default
CORE_LATENCY     ?= 1
AGE_INTERVAL     ?= 4096
STRATEGY_DEFINES ?=
TRACE_DBG_CYCLES ?= 40
TRACE_OUT        ?= sim/tb/traces/ws$(TRACE_WORKSET)_$(TRACE_PATTERN).trace
TRACE_FILE       ?= ../../$(TRACE_OUT)
TRACE_MAX_CYCLES ?= 1000000
TRACE_SWEEP_WORKSETS ?= 32 128 512 2048
MERMAID_PATTERN ?= mixed
MERMAID_WORKSET ?= 8
MERMAID_FULLSET ?= 0
MERMAID_STEPS   ?= 12
MERMAID_SEED    ?= 1
MERMAID_DEEP_LEN ?= 0
MERMAID_DEEP_AT  ?= 4
MERMAID_DEEP_START ?= 0
MERMAID_PREDICTOR ?= none
MERMAID_PREDICT_STEPS ?= 0
MERMAID_DIR ?= mermaid_out
MERMAID_OUT ?= $(MERMAID_DIR)/branch_pattern_$(MERMAID_PATTERN).txt

VCS_FLAGS := -sverilog \
             -debug_access+all \
             -lca -kdb \
             -full64 \
             -timescale=1ns/1ps \
             -verdi \
             +warn=noTFMPC \
             -LDFLAGS -Wl,--no-as-needed

ifeq ($(TRACE_CFG),tiny)
TRACE_DEFINES := +define+TAGE_CFG_TINY
else ifeq ($(TRACE_CFG),wide)
TRACE_DEFINES := +define+TAGE_CFG_WIDE
else
TRACE_DEFINES :=
endif

SIM_FLAGS := +fsdb+autoflush
PLUSARGS  ?=
LATENCY_DEFINE := +define+TAGE_CORE_LATENCY=$(CORE_LATENCY) +define+TAGE_AGE_INTERVAL=$(AGE_INTERVAL) $(STRATEGY_DEFINES)

.PHONY: all compile run verdi verdi_sch clean rerun help \
        core core_rerun core_verdi \
        single single_rerun single_verdi \
        overlap overlap_rerun overlap_verdi \
        gen_trace trace trace_rerun trace_verdi trace_sweep mermaid mermaid_suite

all: core

compile:
	@echo "=================================================="
	@echo " [VCS] compiling $(FLIST_PATH)"
	@echo "=================================================="
	cd $(PROJ_ROOT) && mkdir -p $(RUN_DIR) && vcs $(VCS_FLAGS) $(LATENCY_DEFINE) -Mdir=$(VCS_MDIR) -o $(SIMV) -f $(FLIST_PATH) -l $(RUN_DIR)/compile.log
	@echo " [VCS] done: $(RUN_DIR)/compile.log"

run:
	@echo "=================================================="
	@echo " [SIM] running $(SIMV) for up to $(MAX_CYCLES) cycles"
	@echo "=================================================="
	@if [ ! -f $(PROJ_ROOT)/$(SIMV) ]; then \
		echo "Error: $(SIMV) not found. Please run 'make compile' first."; \
		exit 1; \
	fi
	cd $(PROJ_ROOT)/$(RUN_DIR) && ./simv +max_cycles=$(MAX_CYCLES) $(PLUSARGS) $(SIM_FLAGS) -l sim.log
	@echo " [SIM] done"

verdi:
	@echo "=================================================="
	@echo " [VERDI] loading $(FSDB_FILE)"
	@echo " [VERDI] working directory: $(RUN_DIR)"
	@echo "=================================================="
	@if [ ! -f $(PROJ_ROOT)/$(FSDB_FILE) ]; then \
		echo "Error: waveform '$(FSDB_FILE)' not found. Please run 'make run' first."; \
		exit 1; \
	fi
	cd $(PROJ_ROOT) && mkdir -p $(RUN_DIR) && sed 's#^\./#../../#' $(FLIST_PATH) > $(VERDI_FLIST)
	cd $(PROJ_ROOT)/$(RUN_DIR) && verdi -sv -f verdi_$(FLIST) -ssf $(FSDB_NAME) &

verdi_sch:
	cd $(PROJ_ROOT) && mkdir -p $(RUN_DIR)
	cd $(PROJ_ROOT) && sed 's#^\./#../../#' $(FLIST_PATH) > $(VERDI_FLIST)
	cd $(PROJ_ROOT)/$(RUN_DIR) && verdi -sv -f verdi_$(FLIST) &

clean:
	@echo "cleaning simulation outputs..."
	cd $(PROJ_ROOT) && rm -rf $(RUN_DIR) simv* csrc* *.log *.key *.vpd *.vdb *.fsdb inter.fsdb* verdiLog novas.* BSS*.log DVEfiles .inter.fsdb.tbsim .vcs_checkpoint_shared_memory.*
	cd $(PROJ_ROOT) && mkdir -p $(RUN_DIR)
	@echo "clean done"

rerun: compile run verdi

core: FLIST := core.f
core: FSDB_NAME := tb_tage_predictor_core.fsdb
core: compile run

core_rerun: FLIST := core.f
core_rerun: FSDB_NAME := tb_tage_predictor_core.fsdb
core_rerun: rerun

core_verdi: FLIST := core.f
core_verdi: FSDB_NAME := tb_tage_predictor_core.fsdb
core_verdi: verdi

single: FLIST := wrapper_single.f
single: FSDB_NAME := tb_tage_predictor_single_outstanding.fsdb
single: compile run

single_rerun: FLIST := wrapper_single.f
single_rerun: FSDB_NAME := tb_tage_predictor_single_outstanding.fsdb
single_rerun: rerun

single_verdi: FLIST := wrapper_single.f
single_verdi: FSDB_NAME := tb_tage_predictor_single_outstanding.fsdb
single_verdi: verdi

overlap: FLIST := wrapper_overlap.f
overlap: FSDB_NAME := tb_tage_predictor_overlap_update_predict.fsdb
overlap: compile run

overlap_rerun: FLIST := wrapper_overlap.f
overlap_rerun: FSDB_NAME := tb_tage_predictor_overlap_update_predict.fsdb
overlap_rerun: rerun

overlap_verdi: FLIST := wrapper_overlap.f
overlap_verdi: FSDB_NAME := tb_tage_predictor_overlap_update_predict.fsdb
overlap_verdi: verdi

gen_trace:
	@echo "=================================================="
	@echo " [TRACE] generating $(TRACE_OUT)"
	@echo "=================================================="
	cd $(PROJ_ROOT) && python3 sim/tb/gen_trace.py \
		--workset $(TRACE_WORKSET) \
		--branches $(TRACE_BRANCHES) \
		--pattern $(TRACE_PATTERN) \
		--body-len $(TRACE_BODY_LEN) \
		--body-len-min $(TRACE_BODY_LEN_MIN) \
		--body-len-max $(TRACE_BODY_LEN_MAX) \
		--deep-len $(TRACE_DEEP_LEN) \
		--deep-period $(TRACE_DEEP_PERIOD) \
		--deep-start $(TRACE_DEEP_START) \
		--seed $(TRACE_SEED) \
		--out $(TRACE_OUT)
	@echo " [TRACE] done"

trace: FLIST := wrapper_trace.f
trace: FSDB_NAME := tb_tage_predictor_trace.fsdb
trace: MAX_CYCLES := $(TRACE_MAX_CYCLES)
trace: VCS_FLAGS += $(TRACE_DEFINES)
trace: PLUSARGS := +trace=$(TRACE_FILE) +warmup=$(TRACE_WARMUP) +dbg_cycles=$(TRACE_DBG_CYCLES)
trace: gen_trace compile run

trace_rerun: FLIST := wrapper_trace.f
trace_rerun: FSDB_NAME := tb_tage_predictor_trace.fsdb
trace_rerun: MAX_CYCLES := $(TRACE_MAX_CYCLES)
trace_rerun: VCS_FLAGS += $(TRACE_DEFINES)
trace_rerun: PLUSARGS := +trace=$(TRACE_FILE) +warmup=$(TRACE_WARMUP) +dbg_cycles=$(TRACE_DBG_CYCLES)
trace_rerun: gen_trace rerun

trace_verdi: FLIST := wrapper_trace.f
trace_verdi: FSDB_NAME := tb_tage_predictor_trace.fsdb
trace_verdi: verdi

trace_sweep:
	@for ws in $(TRACE_SWEEP_WORKSETS); do \
		echo "=================================================="; \
		echo " [SWEEP] TRACE_WORKSET=$$ws TRACE_PATTERN=$(TRACE_PATTERN)"; \
		echo "=================================================="; \
		$(MAKE) trace TRACE_WORKSET=$$ws TRACE_PATTERN=$(TRACE_PATTERN) \
			TRACE_BRANCHES=$(TRACE_BRANCHES) TRACE_WARMUP=$(TRACE_WARMUP) \
			TRACE_BODY_LEN=$(TRACE_BODY_LEN) TRACE_SEED=$(TRACE_SEED) \
			TRACE_BODY_LEN_MIN=$(TRACE_BODY_LEN_MIN) TRACE_BODY_LEN_MAX=$(TRACE_BODY_LEN_MAX) \
			TRACE_DEEP_LEN=$(TRACE_DEEP_LEN) TRACE_DEEP_PERIOD=$(TRACE_DEEP_PERIOD) \
			TRACE_DEEP_START=$(TRACE_DEEP_START) \
			TRACE_CFG=$(TRACE_CFG) CORE_LATENCY=$(CORE_LATENCY) AGE_INTERVAL=$(AGE_INTERVAL) STRATEGY_DEFINES="$(STRATEGY_DEFINES)" TRACE_DBG_CYCLES=$(TRACE_DBG_CYCLES) \
			TRACE_MAX_CYCLES=$(TRACE_MAX_CYCLES) || exit 1; \
	done

mermaid:
	@echo "=================================================="
	@echo " [MERMAID] generating $(MERMAID_OUT)"
	@echo "=================================================="
	cd $(PROJ_ROOT) && mkdir -p $(MERMAID_DIR) && python3 sim/tb/gen_mermaid.py \
		--pattern $(MERMAID_PATTERN) \
		--workset $(MERMAID_WORKSET) \
		--fullset $(MERMAID_FULLSET) \
		--steps $(MERMAID_STEPS) \
		--seed $(MERMAID_SEED) \
		--deep-len $(MERMAID_DEEP_LEN) \
		--deep-at $(MERMAID_DEEP_AT) \
		--deep-start $(MERMAID_DEEP_START) \
		--predictor $(MERMAID_PREDICTOR) \
		--predict-steps $(MERMAID_PREDICT_STEPS) \
		> $(MERMAID_OUT)
	@echo " [MERMAID] done: $(MERMAID_OUT)"

mermaid_suite:
	@echo "=================================================="
	@echo " [MERMAID] generating suite in $(MERMAID_DIR)"
	@echo "=================================================="
	cd $(PROJ_ROOT) && mkdir -p $(MERMAID_DIR) && python3 sim/tb/gen_mermaid.py --pattern loop --workset 6 --fullset 10 --steps 12 --seed 1 > $(MERMAID_DIR)/01_loop_workset.txt
	cd $(PROJ_ROOT) && mkdir -p $(MERMAID_DIR) && python3 sim/tb/gen_mermaid.py --pattern nested --workset 6 --fullset 10 --steps 12 --seed 1 > $(MERMAID_DIR)/02_nested_workset.txt
	cd $(PROJ_ROOT) && mkdir -p $(MERMAID_DIR) && python3 sim/tb/gen_mermaid.py --pattern correlated --workset 8 --fullset 12 --steps 14 --seed 1 > $(MERMAID_DIR)/03_correlated_workset.txt
	cd $(PROJ_ROOT) && mkdir -p $(MERMAID_DIR) && python3 sim/tb/gen_mermaid.py --pattern random --workset 8 --fullset 12 --steps 14 --seed 3 > $(MERMAID_DIR)/04_random_workset.txt
	cd $(PROJ_ROOT) && mkdir -p $(MERMAID_DIR) && python3 sim/tb/gen_mermaid.py --pattern mixed --workset 10 --fullset 16 --steps 18 --seed 1 > $(MERMAID_DIR)/05_mixed_workset.txt
	cd $(PROJ_ROOT) && mkdir -p $(MERMAID_DIR) && python3 sim/tb/gen_mermaid.py --pattern mixed --workset 10 --fullset 16 --steps 18 --seed 1 --deep-len 6 --deep-at 4 > $(MERMAID_DIR)/06_mixed_deep_burst.txt
	cd $(PROJ_ROOT) && mkdir -p $(MERMAID_DIR) && python3 sim/tb/gen_mermaid.py --pattern mixed --workset 10 --fullset 16 --steps 12 --seed 1 --predictor last_outcome --predict-steps 4 > $(MERMAID_DIR)/07_workset_gt_prediction_set.txt
	cd $(PROJ_ROOT) && mkdir -p $(MERMAID_DIR) && python3 sim/tb/gen_mermaid.py --pattern mixed --workset 8 --fullset 16 --steps 12 --seed 1 --predictor escape_full > $(MERMAID_DIR)/08_prediction_set_gt_workset.txt
	cd $(PROJ_ROOT) && mkdir -p $(MERMAID_DIR) && python3 sim/tb/gen_mermaid.py --pattern mixed --workset 8 --fullset 16 --steps 12 --seed 1 --predictor always_not_taken > $(MERMAID_DIR)/09_predictor_error_sets.txt
	@echo " [MERMAID] done: $(MERMAID_DIR)"

help:
	@echo "Targets:"
	@echo "  make core       - compile and run core test"
	@echo "  make single     - compile and run wrapper single-outstanding test"
	@echo "  make overlap    - compile and run wrapper overlap update/predict test"
	@echo "  make trace      - generate a CFG-like trace and compare wrapper against core"
	@echo "  make trace_sweep - run trace over TRACE_SWEEP_WORKSETS='32 128 512 2048'"
	@echo "  make mermaid    - write a Mermaid graph to MERMAID_OUT"
	@echo "  make mermaid_suite - write standard Mermaid txt files to MERMAID_DIR"
	@echo "  make trace_verdi - open trace waveform; Verdi logs stay under sim/01"
	@echo "  make compile    - compile FLIST=<file>, default core.f"
	@echo "  make run        - run current sim/01/simv"
	@echo "  make verdi      - open FSDB_NAME=<file>, default core waveform"
	@echo "  make clean      - clean sim/01 and root simulation outputs"
	@echo ""
	@echo "Trace knobs:"
	@echo "  TRACE_WORKSET=128 TRACE_PATTERN=mixed TRACE_BRANCHES=100000"
	@echo "  TRACE_WARMUP=10000 TRACE_BODY_LEN=-1 TRACE_BODY_LEN_MIN=0 TRACE_BODY_LEN_MAX=15 TRACE_SEED=1"
	@echo "  TRACE_DEEP_LEN=0 TRACE_DEEP_PERIOD=2048 TRACE_DEEP_START=0"
	@echo "  TRACE_CFG=default|tiny|wide CORE_LATENCY=1|2 AGE_INTERVAL=4096 TRACE_DBG_CYCLES=40"
	@echo "  MERMAID_PATTERN=mixed MERMAID_WORKSET=8 MERMAID_FULLSET=0 MERMAID_STEPS=12 MERMAID_DEEP_LEN=0 MERMAID_PREDICTOR=none MERMAID_PREDICT_STEPS=0 MERMAID_OUT=mermaid_out/branch_pattern_mixed.txt"
