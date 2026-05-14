"""DSPy-driven optimizer for the OpenFlow transcript cleanup prompt.

See scripts/optimize_prompt/README.md for usage.
"""

import os
import re
import sys
import textwrap
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
        train_raw = ds["train"]
        rest_split = ds["test"].train_test_split(test_size=0.5, seed=seed)
        val_raw = rest_split["train"]
        test_raw = rest_split["test"]
    else:
        full: Dataset = ds["train"] if "train" in ds else next(iter(ds.values()))
        first = full.train_test_split(test_size=0.4, seed=seed)
        train_raw = first["train"]
        second = first["test"].train_test_split(test_size=0.5, seed=seed)
        val_raw = second["train"]
        test_raw = second["test"]

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
    lm = dspy.LM(qualified, temperature=0.0, max_tokens=512)
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
    del trace
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
