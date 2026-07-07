#!/usr/bin/env python3
"""Generate Mermaid control-flow diagrams for trace-generator patterns.

Black arrows describe the static program branch space:
    NT = BRRES 0 target, TK = BRRES 1 target.

Red arrows describe one dynamic path produced by the same branch-result rules
used by gen_trace.py.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass


class XorShift32:
    def __init__(self, seed: int) -> None:
        self.state = seed & 0xFFFFFFFF or 1

    def next(self) -> int:
        x = self.state
        x ^= (x << 13) & 0xFFFFFFFF
        x ^= (x >> 17) & 0xFFFFFFFF
        x ^= (x << 5) & 0xFFFFFFFF
        self.state = x & 0xFFFFFFFF
        return self.state

    def bit(self) -> int:
        return (self.next() >> 31) & 1

    def randint(self, limit: int) -> int:
        return self.next() % limit


@dataclass
class BranchState:
    loop_count: int
    loop_period: int
    bias: int


def branch_targets(idx: int, workset: int, pattern: str) -> tuple[int, int]:
    nt_idx = (idx + 1) % workset
    if pattern == "loop":
        tk_idx = idx
    elif pattern == "nested":
        tk_idx = idx if (idx % 2 == 0) else (idx + workset - 1) % workset
    elif pattern == "correlated":
        tk_idx = (idx * 17 + 3) % workset
    elif pattern == "random":
        tk_idx = (idx * 5 + 1) % workset
    else:
        kind = idx % 10
        if kind <= 5:
            tk_idx = idx
        elif kind <= 7:
            tk_idx = (idx * 17 + 3) % workset
        elif kind == 8:
            tk_idx = (idx + 4) % workset
        else:
            tk_idx = (idx * 5 + 1) % workset
    return nt_idx, tk_idx


def build_states(workset: int, seed: int) -> list[BranchState]:
    rng = XorShift32(seed)
    states: list[BranchState] = []
    for idx in range(workset):
        period = 4 + (idx * 7 + rng.randint(17)) % 29
        bias = 70 + (idx * 11 + rng.randint(20)) % 25
        states.append(BranchState(loop_count=0, loop_period=period, bias=bias))
    return states


def branch_result(
    idx: int,
    pattern: str,
    states: list[BranchState],
    rng: XorShift32,
    last_result: int,
) -> int:
    state = states[idx]

    if pattern == "loop":
        state.loop_count = (state.loop_count + 1) % state.loop_period
        return 0 if state.loop_count == 0 else 1

    if pattern == "nested":
        if idx % 2 == 0:
            state.loop_count = (state.loop_count + 1) % state.loop_period
            return 0 if state.loop_count == 0 else 1
        state.loop_count = (state.loop_count + 1) % (state.loop_period + 3)
        return 0 if state.loop_count == 0 else 1

    if pattern == "correlated":
        return last_result ^ ((idx >> 1) & 1)

    if pattern == "random":
        return rng.bit()

    kind = idx % 10
    if kind <= 5:
        state.loop_count = (state.loop_count + 1) % state.loop_period
        return 0 if state.loop_count == 0 else 1
    if kind <= 7:
        return last_result ^ (idx & 1)
    if kind == 8:
        return 1 if rng.randint(100) < state.bias else 0
    return rng.bit()


def dynamic_path(args: argparse.Namespace) -> list[tuple[int, int, int]]:
    rng = XorShift32(args.seed)
    states = build_states(args.workset, args.seed)
    path: list[tuple[int, int, int]] = []
    current_idx = 0
    last_result = 0

    for step in range(args.steps):
        if args.deep_len > 0 and step == args.deep_at:
            normal_next, _ = branch_targets(current_idx, args.workset, args.pattern)
            deep_start = args.deep_start % args.workset
            path.append((current_idx, 1, deep_start))
            for pos in range(args.deep_len):
                src = (deep_start + pos) % args.workset
                is_last = pos == args.deep_len - 1
                dst = normal_next if is_last else (deep_start + pos + 1) % args.workset
                path.append((src, 0 if is_last else 1, dst))
            current_idx = normal_next
            last_result = 0
            continue

        result = branch_result(current_idx, args.pattern, states, rng, last_result)
        nt_idx, tk_idx = branch_targets(current_idx, args.workset, args.pattern)
        next_idx = tk_idx if result else nt_idx
        path.append((current_idx, result, next_idx))
        current_idx = next_idx
        last_result = result

    return path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--workset", type=int, default=8)
    parser.add_argument("--pattern", choices=["loop", "nested", "correlated", "random", "mixed"], default="mixed")
    parser.add_argument("--steps", type=int, default=12)
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--deep-len", type=int, default=0)
    parser.add_argument("--deep-at", type=int, default=4)
    parser.add_argument("--deep-start", type=int, default=0)
    args = parser.parse_args()

    if args.workset <= 0:
        raise SystemExit("--workset must be positive")
    if args.steps <= 0:
        raise SystemExit("--steps must be positive")
    if args.deep_len < 0:
        raise SystemExit("--deep-len must be non-negative")

    print("```mermaid")
    print("flowchart LR")
    print('  classDef node fill:#fff,stroke:#111;')
    print('  classDef note fill:#fff7f7,stroke:#d33;')
    print(f'  note["pattern={args.pattern}, workset={args.workset}, steps={args.steps}"]:::note')
    for idx in range(args.workset):
        print(f'  B{idx}(("B{idx}")):::node')

    for idx in range(args.workset):
        nt_idx, tk_idx = branch_targets(idx, args.workset, args.pattern)
        print(f"  B{idx} -->|NT/0| B{nt_idx}")
        print(f"  B{idx} -->|TK/1| B{tk_idx}")

    path = dynamic_path(args)
    for step, (src, result, dst) in enumerate(path):
        label = f"a{step}:{'TK' if result else 'NT'}"
        print(f"  B{src} ==>|{label}| B{dst}")

    static_edges = args.workset * 2
    for edge_idx in range(static_edges):
        print(f"  linkStyle {edge_idx} stroke:#111,stroke-width:1px;")
    for edge_idx in range(static_edges, static_edges + len(path)):
        print(f"  linkStyle {edge_idx} stroke:#d33,stroke-width:3px;")
    print("```")


if __name__ == "__main__":
    main()
