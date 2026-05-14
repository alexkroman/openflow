# OpenFlow cleanup prompt optimizer

A DSPy-driven script that iterates the system prompt in
`Sources/OpenFlowEngine/LLM/StylingPrompt.swift` against the HuggingFace
dataset `shantanugoel/aawaaz-transcript-cleanup-dataset`, emitting an
optimized prompt as a `.txt` file.

## Setup

```bash
cd scripts/optimize_prompt
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

export ANTHROPIC_API_KEY=sk-ant-...   # or OPENAI_API_KEY for --provider openai
```

## Run (hosted proxy — fast, has transfer risk)

```bash
python optimize_prompt.py                       # defaults: anthropic, mipro, 200 train
python optimize_prompt.py --max-train 50        # cheaper smoke run
python optimize_prompt.py --optimizer bootstrap # fewer tokens than MIPROv2
python optimize_prompt.py --provider openai --model gpt-4o-mini
```

Output is written to `out/optimized_prompt.txt`.

## Run (local Qwen via mlx-lm.server — no transfer risk, slow)

To drive DSPy directly against the production Qwen3.5-2B model, run an
mlx-lm.server in another terminal first:

```bash
# Terminal 1: start the model server (downloads the model on first run)
pip install mlx-lm
mlx_lm.server --model mlx-community/Qwen3.5-2B-OptiQ-4bit --port 8080
```

```bash
# Terminal 2: point the optimizer at the local server
python optimize_prompt.py --provider local --max-train 20 --max-val 10
```

Override the server URL with `MLX_LM_BASE_URL=http://...:port/v1` if you
run it elsewhere.

Tradeoffs vs hosted:
- **No transfer risk** — DSPy and the production app see the same weights.
- **Much slower** — per-call latency is dominated by local inference. A
  full MIPROv2 run on `--max-train 200` can take hours.
- **Start small** — `--max-train 20 --max-val 10` for a smoke run; scale
  up only if the first results look promising.

## Workflow with the hosted provider

A prompt that scores well on Claude may not transfer cleanly to Qwen3.5-2B,
so the hosted-provider run is **only step 1**:

1. Run this script → review `out/optimized_prompt.txt` and the printed
   per-case report. Look for regressions and surprising rewrites.
2. Validate the new prompt against the real MLX model with the existing
   regression harness (see `Sources/OpenFlowPromptTest/`).
3. Only if the regression suite still passes, hand-merge the relevant
   deltas (rule wording and/or example lines) into `StylingPrompt.swift`.
   Do not paste the entire optimized prompt wholesale — small models drift
   in ways the proxy model can mask.

When you use `--provider local`, the optimizer is already running against
the production model, so the transfer-risk step is moot — but the
regression-suite check is still good hygiene before adopting changes.

## Tests

```bash
python -m pytest -v
```

Tests cover the pure helpers (`similarity`, `extract_seed_prompt`,
`detect_columns`, `render_prompt`). DSPy and HuggingFace calls are not
unit-tested; smoke-test by running the script end-to-end with
`--max-train 5 --max-val 5`.
