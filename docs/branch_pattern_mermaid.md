# Branch Pattern Mermaid Notes

These diagrams describe the same control-flow model used by
`sim/tb/gen_trace.py`.

- Black arrows are the static program branch space.
- `NT/0` means `BRRES=0`, so the dynamic next PC is `BRPC1`.
- `TK/1` means `BRRES=1`, so the dynamic next PC is `BRPC2`.
- Red thick arrows are one actual dynamic path through that static space.

Generate a diagram from the current formulas:

```bash
python3 sim/tb/gen_mermaid.py --pattern loop --workset 6 --steps 12
python3 sim/tb/gen_mermaid.py --pattern nested --workset 6 --steps 12
python3 sim/tb/gen_mermaid.py --pattern correlated --workset 8 --steps 12
python3 sim/tb/gen_mermaid.py --pattern mixed --workset 10 --steps 16 --deep-len 6
```

## Loop

Program structure: every block has a fall-through edge to the next block and a
taken edge back to itself. Actual execution usually stays in the same block for
several taken iterations, then exits by one not-taken edge.

```mermaid
flowchart LR
  classDef node fill:#fff,stroke:#111,color:#111;
  B0(("B0")):::node
  B1(("B1")):::node
  B2(("B2")):::node
  B3(("B3")):::node
  B0 -->|NT/0| B1
  B0 -->|TK/1| B0
  B1 -->|NT/0| B2
  B1 -->|TK/1| B1
  B2 -->|NT/0| B3
  B2 -->|TK/1| B2
  B3 -->|NT/0| B0
  B3 -->|TK/1| B3
  B0 ==>|a0:TK| B0
  B0 ==>|a1:TK| B0
  B0 ==>|a2:NT| B1
  B1 ==>|a3:TK| B1
  B1 ==>|a4:NT| B2
  linkStyle 0,1,2,3,4,5,6,7 stroke:#111,stroke-width:1px,color:#111;
  linkStyle 8,9,10,11,12 stroke:#d33,stroke-width:3px,color:#d33;
```

## Nested

Program structure: even blocks act like local loops; odd blocks jump backward
when taken. This creates small backward regions nested inside the larger ring.

```mermaid
flowchart LR
  classDef node fill:#fff,stroke:#111,color:#111;
  B0(("B0")):::node
  B1(("B1")):::node
  B2(("B2")):::node
  B3(("B3")):::node
  B4(("B4")):::node
  B5(("B5")):::node
  B0 -->|NT/0| B1
  B0 -->|TK/1| B0
  B1 -->|NT/0| B2
  B1 -->|TK/1| B0
  B2 -->|NT/0| B3
  B2 -->|TK/1| B2
  B3 -->|NT/0| B4
  B3 -->|TK/1| B2
  B4 -->|NT/0| B5
  B4 -->|TK/1| B4
  B5 -->|NT/0| B0
  B5 -->|TK/1| B4
  B0 ==>|a0:TK| B0
  B0 ==>|a1:NT| B1
  B1 ==>|a2:TK| B0
  B0 ==>|a3:NT| B1
  B1 ==>|a4:NT| B2
  linkStyle 0,1,2,3,4,5,6,7,8,9,10,11 stroke:#111,stroke-width:1px,color:#111;
  linkStyle 12,13,14,15,16 stroke:#d33,stroke-width:3px,color:#d33;
```

## Correlated

Program structure: not-taken still walks the ring, while taken jumps by the
hash-like mapping `(idx * 17 + 3) % workset`. Actual direction depends on the
previous branch result and the current index, so it is history-correlated.

```mermaid
flowchart LR
  classDef node fill:#fff,stroke:#111,color:#111;
  B0(("B0")):::node
  B1(("B1")):::node
  B2(("B2")):::node
  B3(("B3")):::node
  B4(("B4")):::node
  B5(("B5")):::node
  B6(("B6")):::node
  B7(("B7")):::node
  B0 -->|NT/0| B1
  B0 -->|TK/1| B3
  B1 -->|NT/0| B2
  B1 -->|TK/1| B4
  B2 -->|NT/0| B3
  B2 -->|TK/1| B5
  B3 -->|NT/0| B4
  B3 -->|TK/1| B6
  B4 -->|NT/0| B5
  B4 -->|TK/1| B7
  B5 -->|NT/0| B6
  B5 -->|TK/1| B0
  B6 -->|NT/0| B7
  B6 -->|TK/1| B1
  B7 -->|NT/0| B0
  B7 -->|TK/1| B2
  B0 ==>|a0:NT| B1
  B1 ==>|a1:NT| B2
  B2 ==>|a2:TK| B5
  B5 ==>|a3:TK| B0
  B0 ==>|a4:TK| B3
  linkStyle 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15 stroke:#111,stroke-width:1px,color:#111;
  linkStyle 16,17,18,19,20 stroke:#d33,stroke-width:3px,color:#d33;
```

## Random

Program structure is fixed, but the actual direction is random. This stresses
aliasing and confidence behavior more than learnable loop history.

```bash
python3 sim/tb/gen_mermaid.py --pattern random --workset 8 --steps 12 --seed 3
```

## Mixed

Program structure combines several families by `idx % 10`:

- `0..5`: loop-like self taken edge.
- `6..7`: correlated taken edge.
- `8`: medium forward taken jump.
- `9`: random-style taken target.

This is the default trace shape because it mixes easy, correlated, biased, and
noisy branches in one work set.

```bash
python3 sim/tb/gen_mermaid.py --pattern mixed --workset 10 --steps 18 --seed 1
```

## Deep Burst

`TRACE_DEEP_LEN` inserts a dense chain of branch-only blocks. The program first
takes an entrance edge into the burst. Inside the burst, actual execution keeps
taking to the next burst block, and the last branch exits by not-taken to the
normal successor.

```mermaid
flowchart LR
  classDef node fill:#fff,stroke:#111,color:#111;
  N0(("Normal B0")):::node
  N1(("Normal B1")):::node
  D0(("Deep B0")):::node
  D1(("Deep B1")):::node
  D2(("Deep B2")):::node
  D3(("Deep B3")):::node
  N0 -->|NT/0 normal| N1
  N0 -->|TK/1 enter| D0
  D0 -->|TK/1| D1
  D1 -->|TK/1| D2
  D2 -->|TK/1| D3
  D3 -->|NT/0 exit| N1
  N0 ==>|a0:TK| D0
  D0 ==>|a1:TK| D1
  D1 ==>|a2:TK| D2
  D2 ==>|a3:TK| D3
  D3 ==>|a4:NT| N1
  linkStyle 0,1,2,3,4,5 stroke:#111,stroke-width:1px,color:#111;
  linkStyle 6,7,8,9,10 stroke:#d33,stroke-width:3px,color:#d33;
```

## Body Length

`body_len` changes branch density, not the static branch target formula.

With `body_len=0`, branch blocks are adjacent in time:

```text
B0.branch -> B1.branch -> B2.branch
```

With `body_len=4`, each static block contains four non-branch instructions
before its branch:

```text
B0.i0 -> B0.i1 -> B0.i2 -> B0.i3 -> B0.branch -> next block
```

Non-branch rows consume cycles and check PC flow, but they do not update branch
history in the current predictor tests.
