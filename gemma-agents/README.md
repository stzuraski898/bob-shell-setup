# gemma-agents

Local unit-test generation using **Ollama + Gemma 4**, with an automatic
pytest feedback loop that feeds failures back to the model for correction.

---

## Hardware context (this machine)

| Component | Detail |
|-----------|--------|
| CPU | Intel Core Ultra 7 165H (22 threads, 5 GHz max) |
| RAM | 30 GB total, ~16 GB available |
| GPU | Intel Arc (integrated) + RTX 1000 Ada Laptop (no `nvidia-smi` driver visible) |
| Model | `gemma4:latest` — 9.6 GB on disk |
| Recommended concurrency | **1 agent** to start; test 2 only after benchmarking |

With ~16 GB available RAM and no confirmed CUDA driver, Gemma 4 runs via
CPU/integrated GPU. A second simultaneous instance will compete for memory
and is likely to slow both agents down. Run `ollama ps` while a generation
is in progress to see actual load.

---

## Prerequisites

```bash
# 1. Ollama must be installed and running
ollama serve          # in a separate terminal, or as a systemd service

# 2. Pull the model (already done if you see it in `ollama list`)
ollama pull gemma4:latest

# 3. Python dependencies
pip install ollama pytest
```

---

## Files

| File | Purpose |
|------|---------|
| `launch-gemma-agents.sh` | Launcher — opens Tilix tabs, one per source file |
| `generate_tests.py` | Core agent — generates tests, runs pytest, feeds failures back |
| `Inputs/gemma-instructions` | Instructions file — source/output file pairs |

---

## Quick start

### 1. Edit the instructions file

Open [`Inputs/gemma-instructions`](Inputs/gemma-instructions) and add entries
for each source file you want tests generated for:

```
/absolute/path/to/src/calculator.py
/absolute/path/to/tests/test_calculator.py

/absolute/path/to/src/utils.py
/absolute/path/to/tests/test_utils.py
```

Each entry is two lines: **source file path**, then **output test file path**,
separated by a blank line.

### 2. Run a single agent directly (no Tilix needed)

```bash
python3 generate_tests.py \
    --source /path/to/src/calculator.py \
    --output /path/to/tests/test_calculator.py
```

### 3. Launch via Tilix (multi-tab)

```bash
chmod +x launch-gemma-agents.sh

# Default: 1 agent, gemma4:latest, Inputs/gemma-instructions
./launch-gemma-agents.sh

# Custom instructions file
./launch-gemma-agents.sh --instructions /path/to/my-instructions

# Raise agent cap (benchmark first!)
./launch-gemma-agents.sh --agents 2
```

---

## generate_tests.py options

```
--source <path>          Python source file to generate tests for  [required]
--output <path>          Where to write the generated test file     [required]
--model  <name>          Ollama model name (default: gemma4:latest)
--max-iterations <n>     Feedback-loop attempts before giving up    (default: 5)
--no-feedback            Skip pytest loop; just write the first generated file
```

---

## How the feedback loop works

```
Source code
     │
     ▼
  Gemma 4  ──────────────────────── generates ────────────────────────▶ test file
     ▲                                                                       │
     │                                                                  run pytest
     │                                                                       │
     └──── failing output + source + test file ◀── failures? ───────────────┘
                (up to --max-iterations times)
                                                    all pass? → ✅  done
```

1. Gemma generates an initial test file.
2. `pytest` runs against it.
3. If tests fail, the source + current test code + pytest output are sent back
   to Gemma for a corrected version.
4. Steps 2–3 repeat up to `--max-iterations` times.
5. On success, the test file is left in place and the script exits `0`.
   On exhaustion, it exits `1` with the last attempt on disk.

---

## Benchmarking concurrency

Before raising `--agents` above 1, measure throughput:

```bash
# Terminal 1 — watch model memory usage
watch -n 2 ollama ps

# Terminal 2 — time a single run
time python3 generate_tests.py --source /path/to/module.py --output /tmp/test_bench.py --no-feedback
```

Compare tests-per-minute at 1, 2, and 3 agents. If 2 agents is slower
wall-clock than 1, stay at 1.

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `Ollama is not running` | `ollama serve` in another terminal |
| `the 'ollama' package is not installed` | `pip install ollama` |
| Tests always fail on imports | Ensure the source module's directory is on `PYTHONPATH` or use an absolute import path |
| Very slow generation | Normal for CPU-only. `gemma4:2b` (if available) is faster but lower quality |
| OOM / swap thrashing | Reduce `--agents` to 1 or switch to a smaller model |
