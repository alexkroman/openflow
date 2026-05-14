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
