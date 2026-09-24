#!/usr/bin/env python3
"""
generate_tests.py
-----------------
Uses local Ollama + Gemma 4 to generate pytest unit tests for a Python source
file, then runs pytest and feeds failures back to the model for correction.

Usage:
    python3 generate_tests.py --source path/to/module.py --output path/to/test_module.py
    python3 generate_tests.py --source src/calc.py --output tests/test_calc.py \
        --model gemma4:latest --max-iterations 5 --prompt-file Inputs/prompts/my-prompt.md

The --prompt-file option loads a Markdown or plain-text file whose contents replace
the built-in system prompt. Use this to provide intent artefacts, class contracts,
and project-specific test instructions to the model.

Requirements:
    pip install ollama
    ollama serve  (must be running)
    ollama pull gemma4:latest
    pytest  (for the feedback loop)
"""

import argparse
import os
import re
import subprocess
import sys


def read_source(path: str) -> str:
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def write_tests(path: str, code: str) -> None:
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(code)


def extract_code_block(text: str) -> str:
    """Pull the first fenced ```cpp/python … ``` block.

    Handles three cases:
    1. Properly closed fence  — extract the content between opening and closing ```
    2. Truncated response     — opening ``` present but no closing ```: strip the
                                opening fence line and return the rest as-is
    3. No fence at all        — return the raw text stripped of leading/trailing whitespace
    """
    # Case 1: properly closed fence (```cpp, ```python, ``` etc.)
    match = re.search(r"```(?:\w+)?\s*\n(.*?)```", text, re.DOTALL)
    if match:
        return match.group(1).strip()

    # Case 2: opening fence present but response was truncated before closing ```
    truncated = re.search(r"```(?:\w+)?\s*\n(.*)", text, re.DOTALL)
    if truncated:
        return truncated.group(1).strip()

    # Case 3: no fence — return raw text
    return text.strip()


_DEFAULT_SYSTEM_PROMPT = (
    "You are an expert C++ test engineer working on the Ceph storage system. "
    "Generate high-quality Google Test (gtest) unit tests for the provided C++ source code. "
    "Cover normal cases, edge cases, and error/exception cases. "
    "Use gtest conventions (TEST, TEST_F, EXPECT_EQ, ASSERT_EQ, etc.). "
    "Every test must include EXPECT/ASSERT macros that verify actual values — "
    "not just that the code runs without crashing. A test with no assertions is not acceptable. "
    "Return ONLY the complete C++ test file inside a single ```cpp code block. "
    "Do not include any explanation outside the code block."
)


# Context and output token limits.
# gemma4:latest supports a 131,072-token context window.
# num_ctx:     total tokens the model holds in memory (prompt + response).
#              32,768 is comfortable on 30 GB RAM; raise toward 65,536 if
#              responses are still truncated and memory allows.
# num_predict: maximum tokens the model will generate in one response.
#              16,384 is enough for even the largest test file.
_NUM_CTX = 32_768
_NUM_PREDICT = 16_384


def generate_tests(
    client,
    model: str,
    source_code: str,
    source_path: str,
    system_prompt: str | None = None,
) -> str:
    """Ask Gemma to generate initial unit tests for the given source."""
    print(f"[generate] Asking {model} to generate tests for {source_path} …")
    print(f"           num_ctx={_NUM_CTX}  num_predict={_NUM_PREDICT}")
    prompt = system_prompt if system_prompt is not None else _DEFAULT_SYSTEM_PROMPT
    response = client.chat(
        model=model,
        messages=[
            {
                "role": "system",
                "content": prompt,
            },
            {
                "role": "user",
                "content": (
                    f"Generate unit tests for this source file ({source_path}):\n\n"
                    f"```cpp\n{source_code}\n```"
                ),
            },
        ],
        options={"num_ctx": _NUM_CTX, "num_predict": _NUM_PREDICT},
    )
    return extract_code_block(response["message"]["content"])


def fix_tests(
    client,
    model: str,
    source_code: str,
    source_path: str,
    test_code: str,
    build_output: str,
    iteration: int,
) -> str:
    """Ask Gemma to fix the failing tests given the build/run output."""
    print(f"[fix] Iteration {iteration}: asking {model} to fix failing tests …")
    response = client.chat(
        model=model,
        messages=[
            {
                "role": "system",
                "content": (
                    "You are an expert C++ test engineer working on the Ceph storage system. "
                    "You will be given C++ source code, a failing gtest unit-test file, and the "
                    "build or test-run output. Fix the test file so it compiles and all tests pass. "
                    "Return ONLY the corrected, complete C++ test file inside a single ```cpp code block. "
                    "Do not include any explanation outside the code block."
                ),
            },
            {
                "role": "user",
                "content": (
                    f"Source file ({source_path}):\n\n"
                    f"```cpp\n{source_code}\n```\n\n"
                    f"Failing test file:\n\n"
                    f"```cpp\n{test_code}\n```\n\n"
                    f"Build/test output:\n\n"
                    f"```\n{build_output}\n```\n\n"
                    "Please fix the test file."
                ),
            },
        ],
    )
    return extract_code_block(response["message"]["content"])


def run_pytest(test_path: str) -> tuple[bool, str]:
    """Run pytest on the generated test file. Returns (passed, output).

    NOTE: For C++ gtest output files, the feedback loop is still useful even
    without this runner — the user compiles manually and can paste build output
    back in. This function is retained for Python source targets."""
    result = subprocess.run(
        [sys.executable, "-m", "pytest", test_path, "-v", "--tb=short"],
        capture_output=True,
        text=True,
    )
    output = result.stdout + result.stderr
    passed = result.returncode == 0
    return passed, output


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Generate gtest/pytest unit tests using local Ollama + Gemma 4."
    )
    parser.add_argument(
        "--source", required=True, help="Path to the source file to test."
    )
    parser.add_argument(
        "--output", required=True, help="Where to write the generated test file."
    )
    parser.add_argument(
        "--model",
        default="gemma4:latest",
        help="Ollama model name (default: gemma4:latest).",
    )
    parser.add_argument(
        "--max-iterations",
        type=int,
        default=5,
        help="Max feedback-loop iterations before giving up (default: 5).",
    )
    parser.add_argument(
        "--no-feedback",
        action="store_true",
        help="Disable the feedback loop; just write the first generated tests.",
    )
    parser.add_argument(
        "--prompt-file",
        default=None,
        help=(
            "Path to a .md or .txt file whose contents replace the built-in system prompt. "
            "Use this to supply intent artefacts and class contracts to the model."
        ),
    )
    args = parser.parse_args()

    # Late import so the script fails clearly if ollama isn't installed
    try:
        import ollama  # noqa: PLC0415
    except ImportError:
        print(
            "Error: the 'ollama' Python package is not installed.\n"
            "Run:  pip install ollama",
            file=sys.stderr,
        )
        sys.exit(1)

    if not os.path.isfile(args.source):
        print(f"Error: source file not found: {args.source}", file=sys.stderr)
        sys.exit(1)

    # Load optional custom system prompt
    system_prompt: str | None = None
    if args.prompt_file:
        if not os.path.isfile(args.prompt_file):
            print(f"Error: prompt file not found: {args.prompt_file}", file=sys.stderr)
            sys.exit(1)
        system_prompt = read_source(args.prompt_file)
        print(f"[prompt] Using custom prompt from {args.prompt_file}")

    client = ollama

    source_code = read_source(args.source)

    # --- Initial generation ---
    test_code = generate_tests(client, args.model, source_code, args.source, system_prompt)
    write_tests(args.output, test_code)
    print(f"[write] Test file written to {args.output}")

    if args.no_feedback:
        print("[done] Feedback loop disabled. Exiting.")
        sys.exit(0)

    # --- Feedback loop ---
    for iteration in range(1, args.max_iterations + 1):
        print(f"\n[pytest] Running pytest on {args.output} (attempt {iteration}) …")
        passed, pytest_output = run_pytest(args.output)

        # Truncate very long output so it fits in the model context comfortably
        max_output_chars = 8000
        if len(pytest_output) > max_output_chars:
            pytest_output = pytest_output[:max_output_chars] + "\n… (output truncated)"

        if passed:
            print(f"\n✅  All tests passed on iteration {iteration}!")
            print(f"    Test file: {args.output}")
            sys.exit(0)

        print(f"[pytest] Tests failed on iteration {iteration}. Sending to model for fixes …")
        print(pytest_output)

        if iteration == args.max_iterations:
            print(
                f"\n⚠️  Reached max iterations ({args.max_iterations}). "
                f"Last test file left at {args.output}."
            )
            print("    Review the pytest output above and fix manually if needed.")
            sys.exit(1)

        test_code = fix_tests(
            client,
            args.model,
            source_code,
            args.source,
            test_code,
            pytest_output,
            iteration,
        )
        write_tests(args.output, test_code)
        print(f"[write] Updated test file written to {args.output}")


if __name__ == "__main__":
    main()
