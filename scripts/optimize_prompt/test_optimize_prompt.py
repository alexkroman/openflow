"""Tests for optimize_prompt.py pure helpers."""

import pytest
from optimize_prompt import extract_seed_prompt, similarity


def test_similarity_identical_returns_one():
    assert similarity("hello world", "hello world") == 1.0


def test_similarity_both_empty_returns_one():
    assert similarity("", "") == 1.0


def test_similarity_one_empty_returns_zero():
    assert similarity("", "abc") == 0.0
    assert similarity("abc", "") == 0.0


def test_similarity_is_case_insensitive():
    assert similarity("Hello", "hello") == 1.0


def test_similarity_single_substitution():
    # distance=1, maxLen=4 -> 0.75
    assert similarity("cats", "bats") == pytest.approx(0.75)


def test_similarity_completely_different():
    # "abc" vs "xyz": distance=3, maxLen=3 -> 0.0
    assert similarity("abc", "xyz") == 0.0


def test_extract_seed_prompt_simple(tmp_path):
    swift = tmp_path / "StylingPrompt.swift"
    swift.write_text(
        'public enum StylingPrompt {\n'
        '  public static let system: String = """\n'
        '    hello world\n'
        '    """\n'
        '}\n'
    )
    assert extract_seed_prompt(swift) == "hello world"


def test_extract_seed_prompt_applies_line_continuations(tmp_path):
    swift = tmp_path / "StylingPrompt.swift"
    swift.write_text(
        '  public static let system: String = """\n'
        '    hello \\\n'
        '    world\n'
        '    """\n'
    )
    assert extract_seed_prompt(swift) == "hello world"


def test_extract_seed_prompt_preserves_multiple_lines(tmp_path):
    swift = tmp_path / "StylingPrompt.swift"
    swift.write_text(
        '  public static let system: String = """\n'
        '    line one\n'
        '    line two\n'
        '    """\n'
    )
    assert extract_seed_prompt(swift) == "line one\nline two"


def test_extract_seed_prompt_raises_when_not_found(tmp_path):
    swift = tmp_path / "StylingPrompt.swift"
    swift.write_text("// no prompt here\n")
    with pytest.raises(ValueError, match="Could not find system prompt"):
        extract_seed_prompt(swift)


def test_extract_seed_prompt_against_real_file():
    """Sanity: the real production prompt extracts and starts with the
    documented opening line."""
    from pathlib import Path
    here = Path(__file__).resolve()
    repo_root = here.parents[2]
    real = repo_root / "Sources/OpenFlowEngine/LLM/StylingPrompt.swift"
    body = extract_seed_prompt(real)
    assert body.startswith("You are a transcript-cleanup function.")
    # Line continuations applied: this phrase spans a `\` in the source.
    assert "dictated speech. Output: ONLY the cleaned text" in body


def test_extract_seed_prompt_decodes_escaped_backslash(tmp_path):
    """Swift `\\\\n` source → `\\n` runtime (literal backslash + n)."""
    swift = tmp_path / "StylingPrompt.swift"
    # Source on disk: the body contains the 3 chars `\`, `\`, `n`.
    swift.write_text(
        '  public static let system: String = """\n'
        '    new line\\\\n done\n'
        '    """\n'
    )
    body = extract_seed_prompt(swift)
    # Runtime value should be 2 chars `\n`, not the 3-char source `\\n`.
    assert body == "new line\\n done"


def test_extract_seed_prompt_preserves_blank_line_after_continuation(tmp_path):
    """Swift `\\<nl>` drops only the trailing newline of THAT line.
    A blank line on the following line is preserved."""
    swift = tmp_path / "StylingPrompt.swift"
    swift.write_text(
        '  public static let system: String = """\n'
        '    a \\\n'
        '    \n'
        '    b\n'
        '    """\n'
    )
    body = extract_seed_prompt(swift)
    # `\<nl>` joins line 1 to line 2; line 2 dedents to empty; line 3 stays.
    assert body == "a \nb"


def test_extract_seed_prompt_real_file_has_decoded_newline_token():
    """Regression: the real prompt's `"new line"→\\n` rule should appear in
    the extracted body as the 2-char `\\n`, not the 3-char `\\\\n`."""
    from pathlib import Path
    here = Path(__file__).resolve()
    repo_root = here.parents[2]
    real = repo_root / "Sources/OpenFlowEngine/LLM/StylingPrompt.swift"
    body = extract_seed_prompt(real)
    # 2 chars: backslash + n. Not the 3-char source form.
    assert '"new line"→\\n' in body
    assert '"new line"→\\\\n' not in body


from optimize_prompt import detect_columns


def test_detect_columns_raw_cleaned():
    assert detect_columns(["raw", "cleaned"]) == ("raw", "cleaned")


def test_detect_columns_input_output():
    assert detect_columns(["input", "output"]) == ("input", "output")


def test_detect_columns_transcript_target():
    assert detect_columns(["transcript", "target"]) == ("transcript", "target")


def test_detect_columns_case_insensitive():
    assert detect_columns(["Raw", "Cleaned"]) == ("Raw", "Cleaned")


def test_detect_columns_ignores_extras():
    assert detect_columns(["id", "raw", "cleaned", "speaker"]) == ("raw", "cleaned")


def test_detect_columns_raises_on_no_match():
    with pytest.raises(ValueError, match="Could not auto-detect"):
        detect_columns(["foo", "bar"])


from types import SimpleNamespace
from optimize_prompt import render_prompt


class _FakePredictor:
    def __init__(self, instructions, demos):
        self.signature = SimpleNamespace(instructions=instructions)
        self.demos = demos


class _FakeProgram:
    def __init__(self, predictor):
        self._p = predictor

    def predictors(self):
        return [self._p]


def test_render_prompt_no_demos():
    p = _FakeProgram(_FakePredictor("Clean the input.", []))
    out = render_prompt(p)
    assert "Clean the input." in out
    # No EXAMPLES section when there are no demos.
    assert "EXAMPLES" not in out


def test_render_prompt_with_demos():
    demos = [
        SimpleNamespace(transcript="um hello", cleaned="Hello."),
        SimpleNamespace(transcript="uh world", cleaned="World."),
    ]
    p = _FakeProgram(_FakePredictor("Clean the input.", demos))
    out = render_prompt(p)
    assert "Clean the input." in out
    assert "EXAMPLES" in out
    assert "<transcript>um hello</transcript> → Hello." in out
    assert "<transcript>uh world</transcript> → World." in out


def test_render_prompt_strips_trailing_whitespace():
    p = _FakeProgram(_FakePredictor("Clean.   \n\n", []))
    out = render_prompt(p)
    assert not out.endswith(" ")
    assert not out.endswith("\n\n\n")
