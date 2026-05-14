"""Tests for optimize_prompt.py pure helpers."""

import pytest
from optimize_prompt import similarity


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
