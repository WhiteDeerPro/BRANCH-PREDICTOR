# Branch Predictor

SystemVerilog branch predictor playground. The current implementation is a
TAGE predictor with a wrapper delay path and trace-driven verification; later
predictors such as gshare, ITTAGE, or other variants can be added beside it.

Repository: `WhiteDeerPro/BRANCH-PREDICTOR`

## Current Predictor: TAGE

The current design separates committed branch history from speculative history:

- `commit_*`: updated only by resolved branch results.
- `specu_*`: advanced by prediction requests and restored on mispredict.

Non-branch instructions in trace tests do not advance predictor history. They only consume cycles and check PC flow.

The TAGE core also has two implementation-oriented controls:

- `PREDICT_LATENCY` / wrapper `CORE_LATENCY`: selectable `0`, `1`, or `2`
  cycle prediction output latency. The default wrapper test mode is `1`.
- `AGE_INTERVAL`: useful-bit aging interval. `0` disables aging; otherwise a
  periodic touched-entry aging writeback decrements nonzero useful bits.

## Layout

```text
rtl/
  tage_pkg.sv
  tage_ram_wr.sv
  tage_predictor_core.sv
  tage_predictor.sv

sim/tb/
  makefile
  core.f
  wrapper_single.f
  wrapper_overlap.f
  wrapper_trace.f
  gen_trace.py
  gen_mermaid.py
  tb_tage_predictor_*.sv

docs/
  branch_pattern_mermaid.md
```

Simulation outputs are generated under `sim/01`.

## Quick Start

```bash
make core
make single
make overlap
make trace
```

Open the last generated trace waveform:

```bash
make trace_verdi
```

Verdi is launched from `sim/01`, so generated `verdiLog` and `novas.*` files stay inside the simulation output directory.
The makefile also creates a temporary Verdi filelist in `sim/01` with paths rewritten for that working directory.

Clean generated outputs:

```bash
make clean
```

## Trace Format

Trace rows use:

```text
PC ISBR BRRES BRPC1 BRPC2
```

Meaning:

- `PC`: current instruction PC.
- `ISBR`: `1` for branch, `0` for non-branch.
- `BRRES`: real branch result, `1` taken and `0` not taken.
- `BRPC1`: not-taken next PC.
- `BRPC2`: taken target PC.

For branch rows:

```text
next_pc = BRRES ? BRPC2 : BRPC1
```

For non-branch rows:

```text
next_pc = PC + 4
```

The trace testbench checks this PC flow.

## Work Set

In these tests, a work set is the group of static branch PCs and control-flow
states that the dynamic program stream repeatedly revisits during measurement.
It is not just the number of generated trace rows.

For a loop, the loop body and its repeated control states are the work set. For
an LFSR-like generator, the repeating period can be treated as a simple dynamic
work set. In this repository, `TRACE_WORKSET` controls the number of static
branch states in the generated program fragment, while `TRACE_BRANCHES`
controls how long that fragment is exercised.

## Command Key

Default trace test:

```bash
make trace
```

Workset sweep:

```bash
make trace_sweep
```

Recommended workset commands:

```bash
make trace TRACE_WORKSET=32
make trace TRACE_WORKSET=128
make trace TRACE_WORKSET=512
make trace TRACE_WORKSET=2048
```

Full sweep with the default mixed trace:

```bash
make trace_sweep TRACE_SWEEP_WORKSETS="32 128 512 2048" \
  TRACE_BRANCHES=100000 TRACE_WARMUP=10000 TRACE_MAX_CYCLES=1000000
```

Loop-like branch pattern:

```bash
make trace TRACE_PATTERN=loop TRACE_WORKSET=128 TRACE_BRANCHES=100000
```

Correlated branch pattern:

```bash
make trace TRACE_PATTERN=correlated TRACE_WORKSET=128 TRACE_BRANCHES=100000
```

Random/noisy branch pattern:

```bash
make trace TRACE_PATTERN=random TRACE_WORKSET=128 TRACE_BRANCHES=100000
```

Mixed sparse/dense branch stream:

```bash
make trace TRACE_BODY_LEN=-1 TRACE_BODY_LEN_MIN=0 TRACE_BODY_LEN_MAX=15
```

Fixed dense branch stream:

```bash
make trace TRACE_BODY_LEN=0
```

Fixed sparse branch stream:

```bash
make trace TRACE_BODY_LEN=16 TRACE_MAX_CYCLES=2000000
```

Deep speculative branch burst:

```bash
make trace TRACE_DEEP_LEN=24 TRACE_DEEP_PERIOD=512 TRACE_WORKSET=64
```

TAGE parameter variants:

```bash
make trace TRACE_CFG=default
make trace TRACE_CFG=tiny
make trace TRACE_CFG=wide
```

Core prediction latency:

```bash
make trace CORE_LATENCY=1
make trace CORE_LATENCY=2
```

Useful-bit aging:

```bash
make trace AGE_INTERVAL=4096
make trace AGE_INTERVAL=1024
make trace AGE_INTERVAL=0
```

Front-end debug print window:

```bash
make trace TRACE_DBG_CYCLES=80
make trace TRACE_DBG_CYCLES=0
```

Mermaid branch-pattern diagrams:

```bash
make mermaid MERMAID_PATTERN=loop MERMAID_WORKSET=6 MERMAID_STEPS=12
make mermaid MERMAID_PATTERN=correlated MERMAID_WORKSET=8 MERMAID_STEPS=12
make mermaid MERMAID_PATTERN=mixed MERMAID_WORKSET=10 MERMAID_STEPS=18 MERMAID_DEEP_LEN=6
```

See `docs/branch_pattern_mermaid.md` for static program-space arrows and red
actual-path examples.

## Important Trace Signals

In `tb_tage_predictor_trace.sv`:

- `predict_req_vld`: current trace row is a branch and starts a prediction.
- `wrap_pred_vld` / `ref_pred_vld`: delayed prediction output valid.
- `trace_actual_taken`: real branch result attached to the current trace row.
- `resolve_actual_taken`: delayed real result used when the branch resolves.
- `ref_resolve_vld`: delayed resolved-branch valid.
- `ref_resolve_snap_vld`: delayed snapshot valid for the resolved branch.
- `ref_resolve_wrong`: reference core detected a misprediction.
- `ref_flush_younger`: clears younger delayed snapshot-valid entries after a mispredict.

Same-cycle prediction and update are legal. If an older branch mispredicts, the core restores from the saved snapshot plus `actual_taken`; a new branch in the same cycle predicts using that restored speculative history.

## Trace Generator

Generate a trace manually:

```bash
python3 sim/tb/gen_trace.py \
  --workset 128 \
  --branches 100000 \
  --pattern mixed \
  --body-len -1 \
  --body-len-min 0 \
  --body-len-max 15 \
  --deep-len 24 \
  --deep-period 2048 \
  --out sim/tb/traces/ws128_mixed.trace
```

The makefile normally generates traces automatically before `make trace`.

## Notes

- `TRACE_CFG` only changes table sizes/history/tag LUTs used by the trace testbench instance.
- `CORE_LATENCY` changes when prediction and snapshot outputs become valid.
  The wrapper shortens its feedback snapshot pipe by the same amount, so total
  branch resolve alignment remains `PIPELINE_DEPTH`.
- `AGE_INTERVAL` ages only entries touched by the predictor read path. This
  keeps the design one-read/one-write per table and avoids adding a scan port.
- `NUM_TABLES` is kept consistent with `tage_pkg.sv` because snapshot type widths depend on package parameters.
- Generated traces and simulation outputs are ignored by git.
