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

## Run

```bash
python optimize_prompt.py                       # defaults: anthropic, mipro, 200 train
python optimize_prompt.py --max-train 50        # cheaper smoke run
python optimize_prompt.py --optimizer bootstrap # fewer tokens than MIPROv2
python optimize_prompt.py --provider openai --model gpt-4o-mini
```

Output is written to `out/optimized_prompt.txt`.

## Workflow

The optimizer uses Claude (or OpenAI) as a proxy for the production
Qwen3.5-2B model. A prompt that scores well here may not transfer cleanly
to the small local model, so this script is **only step 1**:

1. Run this script → review `out/optimized_prompt.txt` and the printed
   per-case report. Look for regressions and surprising rewrites.
2. Validate the new prompt against the real MLX model with the existing
   regression harness:

   ```bash
   cd ../..
   swift run openflow-prompt-test \
     scripts/optimize_prompt/out/optimized_prompt.txt \
     path/to/your/cases.json
   ```

3. Only if the 28-case suite still passes, hand-merge the relevant deltas
   (rule wording and/or example lines) into `StylingPrompt.swift`. Do not
   paste the entire optimized prompt wholesale — small models drift in
   ways the proxy model can mask.

## Tests

```bash
python -m pytest -v
```

Tests cover the pure helpers (`similarity`, `extract_seed_prompt`,
`detect_columns`, `render_prompt`). DSPy and HuggingFace calls are not
unit-tested; smoke-test by running the script end-to-end with
`--max-train 5 --max-val 5`.
