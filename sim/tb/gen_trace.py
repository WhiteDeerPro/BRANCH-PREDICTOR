#!/usr/bin/env python3
"""Generate dynamic branch-predictor traces.

Each output row is:
    PC ISBR BRRES BRPC1 BRPC2

PC/BRPC1/BRPC2 are hexadecimal addresses. ISBR marks whether the current
instruction is a branch. BRRES is the real branch direction for branch rows:
0 selects BRPC1 and 1 selects BRPC2.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path


BASE_PC = 0x1000
BLOCK_STRIDE = 0x40


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
    body_len: int


def block_base(idx: int) -> int:
    return BASE_PC + idx * BLOCK_STRIDE


def branch_pc(idx: int, states: list[BranchState]) -> int:
    return block_base(idx) + states[idx].body_len * 4


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


def write_deep_burst(
    out,
    start_idx: int,
    length: int,
    exit_idx: int,
    workset: int,
) -> int:
    if length <= 0:
        return exit_idx

    for pos in range(length):
        idx = (start_idx + pos) % workset
        next_idx = (start_idx + pos + 1) % workset
        is_last = (pos == length - 1)
        pc = block_base(idx)
        nt_pc = block_base(exit_idx)
        tk_pc = block_base(next_idx)
        result = 0 if is_last else 1
        out.write(f"{pc:08x} 1 {result:d} {nt_pc:08x} {tk_pc:08x}\n")
    return exit_idx


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


def choose_body_len(idx: int, args: argparse.Namespace, rng: XorShift32) -> int:
    if args.body_len >= 0:
        return args.body_len

    span = args.body_len_max - args.body_len_min + 1
    if span <= 0:
        raise SystemExit("--body-len-max must be >= --body-len-min")

    kind = idx % 10
    if kind in (0, 5):
        return args.body_len_min
    if kind in (1, 6):
        return args.body_len_min + min(span - 1, 1 + rng.randint(min(span, 4)))
    if kind in (2, 7):
        return args.body_len_min + rng.randint(span)
    if kind in (3, 8):
        return args.body_len_min + (span - 1) // 2
    return args.body_len_max


def build_states(workset: int, args: argparse.Namespace, rng: XorShift32) -> list[BranchState]:
    states: list[BranchState] = []
    for idx in range(workset):
        period = 4 + (idx * 7 + rng.randint(17)) % 29
        bias = 70 + (idx * 11 + rng.randint(20)) % 25
        body_len = choose_body_len(idx, args, rng)
        states.append(BranchState(loop_count=0, loop_period=period, bias=bias, body_len=body_len))
    return states


def generate(args: argparse.Namespace) -> None:
    rng = XorShift32(args.seed)
    states = build_states(args.workset, args, rng)
    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    current_idx = 0
    branches = 0
    last_result = 0
    deep_next_insert = args.deep_period if args.deep_len > 0 else 0

    with out_path.open("w", encoding="ascii") as out:
        out.write("# PC ISBR BRRES BRPC1 BRPC2\n")
        out.write(
            f"# pattern={args.pattern} workset={args.workset} "
            f"branches={args.branches} body_len={args.body_len} "
            f"body_len_min={args.body_len_min} body_len_max={args.body_len_max} "
            f"deep_len={args.deep_len} deep_period={args.deep_period} seed={args.seed}\n"
        )

        while branches < args.branches:
            if args.deep_len > 0 and branches >= deep_next_insert:
                if branches + 1 >= args.branches:
                    break

                body_len = states[current_idx].body_len
                base = block_base(current_idx)
                for slot in range(body_len):
                    pc = base + slot * 4
                    out.write(f"{pc:08x} 0 0 {pc + 4:08x} 00000000\n")

                normal_next_idx, _ = branch_targets(current_idx, args.workset, args.pattern)
                deep_start_idx = args.deep_start % args.workset
                pc = branch_pc(current_idx, states)
                out.write(f"{pc:08x} 1 1 {block_base(normal_next_idx):08x} {block_base(deep_start_idx):08x}\n")
                branches += 1

                burst_len = min(args.deep_len, args.branches - branches)
                current_idx = write_deep_burst(
                    out=out,
                    start_idx=deep_start_idx,
                    length=burst_len,
                    exit_idx=normal_next_idx,
                    workset=args.workset,
                )
                branches += burst_len
                last_result = 0
                deep_next_insert += args.deep_period
                continue

            base = block_base(current_idx)
            body_len = states[current_idx].body_len
            for slot in range(body_len):
                pc = base + slot * 4
                out.write(f"{pc:08x} 0 0 {pc + 4:08x} 00000000\n")

            result = branch_result(current_idx, args.pattern, states, rng, last_result)
            nt_idx, tk_idx = branch_targets(current_idx, args.workset, args.pattern)
            nt_pc = block_base(nt_idx)
            tk_pc = block_base(tk_idx)
            pc = branch_pc(current_idx, states)
            out.write(f"{pc:08x} 1 {result:d} {nt_pc:08x} {tk_pc:08x}\n")

            current_idx = tk_idx if result else nt_idx
            last_result = result
            branches += 1


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--workset", type=int, default=128)
    parser.add_argument("--branches", type=int, default=100000)
    parser.add_argument("--pattern", choices=["loop", "nested", "correlated", "random", "mixed"], default="mixed")
    parser.add_argument("--body-len", type=int, default=-1,
                        help="Fixed non-branch instructions before each branch. Use -1 for mixed density.")
    parser.add_argument("--body-len-min", type=int, default=0)
    parser.add_argument("--body-len-max", type=int, default=15)
    parser.add_argument("--deep-len", type=int, default=0,
                        help="Insert a branch-only burst of this length. 0 disables it.")
    parser.add_argument("--deep-period", type=int, default=2048,
                        help="Insert one deep burst after this many dynamic branch rows.")
    parser.add_argument("--deep-start", type=int, default=0,
                        help="Static block index used as the first PC of the deep burst.")
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--out", default="sim/tb/traces/ws128_mixed.trace")
    args = parser.parse_args()

    if args.workset <= 0:
        raise SystemExit("--workset must be positive")
    if args.branches <= 0:
        raise SystemExit("--branches must be positive")
    if args.body_len < -1:
        raise SystemExit("--body-len must be -1 or non-negative")
    if args.body_len_min < 0:
        raise SystemExit("--body-len-min must be non-negative")
    if args.deep_len < 0:
        raise SystemExit("--deep-len must be non-negative")
    if args.deep_period <= 0:
        raise SystemExit("--deep-period must be positive")

    generate(args)


if __name__ == "__main__":
    main()
