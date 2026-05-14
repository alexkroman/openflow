"""DSPy-driven optimizer for the OpenFlow transcript cleanup prompt.

See scripts/optimize_prompt/README.md for usage.
"""

import argparse
import os
import re
import sys
import textwrap
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from pathlib import Path

import dspy
from datasets import Dataset, DatasetDict, load_dataset


def _levenshtein(a: str, b: str) -> int:
    """Two-row DP edit distance over Unicode chars. Matches the Swift
    implementation at Sources/OpenFlowPromptTest/main.swift:143-157."""
    if not a:
        return len(b)
    if not b:
        return len(a)
    prev = list(range(len(b) + 1))
    curr = [0] * (len(b) + 1)
    for i in range(1, len(a) + 1):
        curr[0] = i
        for j in range(1, len(b) + 1):
            cost = 0 if a[i - 1] == b[j - 1] else 1
            curr[j] = min(curr[j - 1] + 1, prev[j] + 1, prev[j - 1] + cost)
        prev, curr = curr, prev
    return prev[len(b)]


def similarity(a: str, b: str) -> float:
    """1 - normalized Levenshtein on lowercased strings. 1.0 = identical."""
    aa = a.lower()
    bb = b.lower()
    if not aa and not bb:
        return 1.0
    dist = _levenshtein(aa, bb)
    max_len = max(len(aa), len(bb))
    return 1.0 - dist / max_len


_PROMPT_RE = re.compile(
    r'let\s+system\s*:\s*String\s*=\s*"""\n(.*?)\n\s*"""',
    re.DOTALL,
)


def extract_seed_prompt(swift_path: Path) -> str:
    """Read StylingPrompt.swift and return the runtime value of `system`.

    Handles three Swift string features:
      - leading indentation matching the closing `\"\"\"` is stripped
      - `\\<newline><horizontal-ws>` line continuations join lines with no
        space added (Swift drops the trailing newline of that line only;
        blank lines further down are preserved)
      - `\\\\` source → `\\` runtime (the only Swift escape currently used
        in the prompt — `\\n` source becomes the 2-char string `\\n`)
    """
    text = Path(swift_path).read_text()
    m = _PROMPT_RE.search(text)
    if not m:
        raise ValueError(f"Could not find system prompt in {swift_path}")
    body = textwrap.dedent(m.group(1))
    # Line continuations: `\` at end of line + horizontal whitespace on the
    # next line only. Do NOT use `\s*` here — that would also eat newlines,
    # collapsing genuine blank lines after a continuation.
    body = re.sub(r"\\\n[ \t]*", "", body)
    # Swift `\\` source → `\` runtime. Applied after continuations so a
    # source `\\<nl>` (escaped backslash followed by a real newline)
    # survives the first pass and decodes correctly here.
    body = body.replace("\\\\", "\\")
    return body


_INPUT_CANDIDATES = ("raw", "input", "transcript", "original", "source")
_OUTPUT_CANDIDATES = ("cleaned", "output", "target", "clean", "corrected")

_DATASET_ID = "shantanugoel/aawaaz-transcript-cleanup-dataset"

_DEFAULT_MODELS = {
    "anthropic": "claude-haiku-4-5",
    "openai": "gpt-4o-mini",
}

_API_KEY_VARS = {
    "anthropic": "ANTHROPIC_API_KEY",
    "openai": "OPENAI_API_KEY",
}


def detect_columns(column_names: list[str]) -> tuple[str, str]:
    """Pick (input, output) column names from a HF dataset's schema.

    Match is case-insensitive; the returned strings preserve the original
    casing in `column_names` because `datasets` is case-sensitive when
    indexing rows.
    """
    by_lower = {name.lower(): name for name in column_names}
    input_col = next((by_lower[c] for c in _INPUT_CANDIDATES if c in by_lower), None)
    output_col = next((by_lower[c] for c in _OUTPUT_CANDIDATES if c in by_lower), None)
    if not input_col or not output_col:
        raise ValueError(
            f"Could not auto-detect input/output columns from {column_names}. "
            f"Pass --input-col and --output-col explicitly."
        )
    return input_col, output_col


def load_examples(
    input_col: str | None = None,
    output_col: str | None = None,
    max_train: int | None = None,
    max_val: int | None = None,
    seed: int = 0,
) -> tuple[list[dspy.Example], list[dspy.Example], list[dspy.Example]]:
    """Load the aawaaz dataset and return (train, val, test) as dspy.Example lists.

    If the dataset provides train+test, split test 50/50 into val/test.
    Otherwise split the single split 60/20/20. Auto-detect columns when
    `input_col`/`output_col` are None.
    """
    ds = load_dataset(_DATASET_ID)
    if not isinstance(ds, DatasetDict):
        raise TypeError(
            f"Expected DatasetDict from {_DATASET_ID}, got {type(ds).__name__}"
        )

    if "train" in ds and "test" in ds:
        train_raw, rest = ds["train"], ds["test"]
    else:
        full: Dataset = ds["train"] if "train" in ds else next(iter(ds.values()))
        first = full.train_test_split(test_size=0.4, seed=seed)
        train_raw, rest = first["train"], first["test"]
    split = rest.train_test_split(test_size=0.5, seed=seed)
    val_raw, test_raw = split["train"], split["test"]

    if not input_col or not output_col:
        detected_in, detected_out = detect_columns(list(train_raw.column_names))
        input_col = input_col or detected_in
        output_col = output_col or detected_out

    def to_examples(d: Dataset, limit: int | None) -> list[dspy.Example]:
        if limit is not None:
            d = d.select(range(min(limit, len(d))))
        rows: list[dict] = d.to_list()
        return [
            dspy.Example(transcript=row[input_col], cleaned=row[output_col])
            .with_inputs("transcript")
            for row in rows
        ]

    return (
        to_examples(train_raw, max_train),
        to_examples(val_raw, max_val),
        to_examples(test_raw, None),
    )


def configure_lm(provider: str, model: str | None) -> dspy.LM:
    """Build and register a dspy.LM. Exits 2 if the required env var is unset."""
    if provider not in _API_KEY_VARS:
        print(
            f"Unknown provider {provider!r}; expected one of {list(_API_KEY_VARS)}.",
            file=sys.stderr,
        )
        sys.exit(2)
    env_var = _API_KEY_VARS[provider]
    if not os.environ.get(env_var):
        print(f"Missing {env_var}. Export it and re-run.", file=sys.stderr)
        sys.exit(2)
    model_name = model or _DEFAULT_MODELS[provider]
    qualified = f"{provider}/{model_name}"
    lm = dspy.LM(qualified, temperature=0.0, max_tokens=4096)
    dspy.configure(lm=lm)
    return lm


def build_program(seed_prompt: str) -> dspy.Predict:
    """Build a dspy.Predict module whose signature instructions are the
    current production prompt."""
    sig = dspy.Signature(
        "transcript -> cleaned",  # pyright: ignore[reportCallIssue]
        instructions=seed_prompt,
    )
    return dspy.Predict(sig)  # pyright: ignore[reportArgumentType]


def cleanup_metric(example, pred, trace=None) -> float:  # noqa: ARG001
    """DSPy-compatible metric: similarity between pred.cleaned and the gold
    example.cleaned. `trace` is part of the DSPy metric contract; unused here."""
    _ = trace
    predicted = getattr(pred, "cleaned", "") or ""
    return similarity(predicted, example.cleaned)


def optimize(
    program: dspy.Predict,
    trainset: list[dspy.Example],
    valset: list[dspy.Example],
    method: str = "mipro",
) -> dspy.Predict:
    """Run the chosen optimizer and return the compiled program."""
    if method == "mipro":
        optimizer = dspy.MIPROv2(metric=cleanup_metric, auto="light")
        return optimizer.compile(
            student=program,
            trainset=trainset,
            valset=valset,
            requires_permission_to_run=False,
        )
    if method == "bootstrap":
        optimizer = dspy.BootstrapFewShotWithRandomSearch(
            metric=cleanup_metric,
            max_bootstrapped_demos=4,
            num_candidate_programs=8,
        )
        return optimizer.compile(student=program, trainset=trainset, valset=valset)
    raise ValueError(f"Unknown optimizer method {method!r}")


@dataclass
class CaseResult:
    example_id: int
    transcript: str
    gold: str
    baseline: str
    optimized: str
    baseline_score: float
    optimized_score: float

    @property
    def delta(self) -> float:
        return self.optimized_score - self.baseline_score


_EVAL_THREADS = 8


def _safe_predict(program: dspy.Predict, transcript: str) -> str:
    """Run one prediction; convert any failure into an `<<error: …>>` string so
    a single bad row does not abort the whole evaluation."""
    try:
        return program(transcript=transcript).cleaned or ""  # pyright: ignore[reportCallIssue]
    except Exception as exc:  # noqa: BLE001
        return f"<<error: {exc}>>"


def evaluate(
    baseline: dspy.Predict,
    optimized: dspy.Predict,
    testset: list[dspy.Example],
) -> list[CaseResult]:
    """Run both programs over the test set and collect per-case scores.

    Cases are evaluated in a thread pool; DSPy's LM client is thread-safe
    (MIPROv2's own evaluator uses the same pattern). Order is preserved.
    """
    def score(item: tuple[int, dspy.Example]) -> CaseResult:
        i, ex = item
        b_out = _safe_predict(baseline, ex.transcript)
        o_out = _safe_predict(optimized, ex.transcript)
        return CaseResult(
            example_id=i,
            transcript=ex.transcript,
            gold=ex.cleaned,
            baseline=b_out,
            optimized=o_out,
            baseline_score=similarity(b_out, ex.cleaned),
            optimized_score=similarity(o_out, ex.cleaned),
        )

    with ThreadPoolExecutor(max_workers=_EVAL_THREADS) as pool:
        return list(pool.map(score, enumerate(testset)))


def print_report(results: list[CaseResult]) -> None:
    """Print per-case scores and aggregate means + regression list."""
    print(f"\n{'id':>4}  {'baseline':>8}  {'optimized':>9}  {'delta':>6}  preview")
    print("-" * 78)
    for r in results:
        preview = r.transcript[:40].replace("\n", " ")
        print(
            f"{r.example_id:>4}  {r.baseline_score:>8.3f}  "
            f"{r.optimized_score:>9.3f}  {r.delta:>+6.3f}  {preview}"
        )
    n = max(len(results), 1)
    base_mean = sum(r.baseline_score for r in results) / n
    opt_mean = sum(r.optimized_score for r in results) / n
    print("-" * 78)
    print(f"mean baseline:  {base_mean:.3f}")
    print(f"mean optimized: {opt_mean:.3f}")
    print(f"delta:          {opt_mean - base_mean:+.3f}")
    regressions = [r for r in results if r.delta < -0.05]
    if regressions:
        print(f"\n{len(regressions)} regression(s) (delta < -0.05):")
        for r in regressions:
            print(f"  case {r.example_id}: {r.delta:+.3f}")
            print(f"    gold:      {r.gold!r}")
            print(f"    baseline:  {r.baseline!r}")
            print(f"    optimized: {r.optimized!r}")


def render_prompt(compiled) -> str:
    """Serialize a compiled DSPy program back into a single text block
    suitable for pasting into StylingPrompt.swift.

    Format: instructions, then (if demos exist) a blank line, "EXAMPLES",
    and one `<transcript>X</transcript> → Y` line per demo.
    """
    predictor = compiled.predictors()[0]
    instructions = (predictor.signature.instructions or "").rstrip()
    demos = list(predictor.demos or [])
    parts = [instructions]
    if demos:
        parts.append("")
        parts.append("EXAMPLES")
        for d in demos:
            transcript = getattr(d, "transcript", "")
            cleaned = getattr(d, "cleaned", "")
            parts.append(f"<transcript>{transcript}</transcript> → {cleaned}")
    return "\n".join(parts).rstrip() + "\n"


_REPO_ROOT = Path(__file__).resolve().parents[2]
_SWIFT_PROMPT = _REPO_ROOT / "Sources/OpenFlowEngine/LLM/StylingPrompt.swift"
_DEFAULT_OUT = Path(__file__).resolve().parent / "out" / "optimized_prompt.txt"


def _parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Optimize the OpenFlow cleanup prompt against the aawaaz dataset.",
    )
    p.add_argument("--provider", choices=("anthropic", "openai"), default="anthropic")
    p.add_argument(
        "--model",
        default=None,
        help="model name (default: claude-haiku-4-5 / gpt-4o-mini)",
    )
    p.add_argument("--optimizer", choices=("mipro", "bootstrap"), default="mipro")
    p.add_argument("--max-train", type=int, default=200)
    p.add_argument("--max-val", type=int, default=100)
    p.add_argument("--input-col", default=None)
    p.add_argument("--output-col", default=None)
    p.add_argument("--out", type=Path, default=_DEFAULT_OUT)
    p.add_argument("--swift-prompt", type=Path, default=_SWIFT_PROMPT)
    return p.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(argv)

    print(f"Reading seed prompt from {args.swift_prompt}")
    seed = extract_seed_prompt(args.swift_prompt)
    print(f"Seed prompt: {len(seed)} chars")

    print(f"Configuring LM: {args.provider}")
    configure_lm(args.provider, args.model)

    print("Loading dataset...")
    train, val, test = load_examples(
        input_col=args.input_col,
        output_col=args.output_col,
        max_train=args.max_train,
        max_val=args.max_val,
    )
    print(f"Train={len(train)}  Val={len(val)}  Test={len(test)}")

    baseline = build_program(seed)

    print(f"Running optimizer ({args.optimizer})...")
    try:
        optimized = optimize(baseline, train, val, method=args.optimizer)
    except Exception:
        # Save the baseline render as a partial so a long run isn't lost.
        partial = args.out.with_suffix(".partial.txt")
        partial.parent.mkdir(parents=True, exist_ok=True)
        partial.write_text(render_prompt(baseline))
        print(f"Optimizer failed; saved baseline render to {partial}", file=sys.stderr)
        raise

    print("Evaluating on held-out test split...")
    results = evaluate(baseline, optimized, test)
    print_report(results)

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(render_prompt(optimized))
    print(f"\nWrote optimized prompt to {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
