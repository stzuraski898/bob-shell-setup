import os, glob, re, json

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(SCRIPT_DIR)

def build_data():
    files = sorted(glob.glob(os.path.join(REPO_ROOT, "Outputs", "Intents", "*-intent.md")))
    
    non_func_titles = {
        "files at head", "notable structural events", "lock ordering",
        "lock ordering and invariants", "cross-cutting invariants", "findings summary",
        "self-check", "commit inventory", "rename chain", "data model",
        "architecture summary", "virtual pure interface functions",
        "commit history summary", "design intent", "corpus summary",
        "function index", "class overview", "assessment scope",
        "historical contracts", "corpus metadata", "commit log",
        "cross-cutting analysis", "corpus overview", "function inventory",
        "diverged findings summary", "ungrounded findings summary",
        "locking contract", "notify routing contract", "functions inventory",
        "per-function intent and critique", "summary of findings",
        "header-only functions", "class design intent", "class-level invariants",
        "design purpose", "invariant catalogue", "1. corpus summary", "2. function inventory",
        "3. function-by-function analysis", "4. findings summary", "5. invariant catalogue", "6. self-check",
        "1. commit inventory", "2. rename chain", "3. data model", "4. function analyses",
        "1. commit history summary", "2. rename chain", "3. design intent (established by 5aac7eba, tracker #42079)", "4. function analyses"
    }

    results = []

    for f in files:
        obj = os.path.basename(f).replace("-intent.md", "")
        with open(f, "r", encoding="utf-8") as fh:
            text = fh.read()
            
        lines = text.split("\n")
        
        # Extract metadata
        head_sha = "8681fa6ebac230f86eb445bf57095c63e7f1abcc"
        m = re.search(r"\b(?:HEAD SHA|Corpus HEAD)[:\s*`]+([a-f0-9]{8,40})", text, re.I)
        if m: head_sha = m.group(1)

        date_str = ""
        m = re.search(r"\b(?:Generated|Assessment date|Corpus collected at)[:\s*`]+([^\n\r`]+)", text, re.I)
        if m: date_str = m.group(1).strip()
        
        commits_count = 0
        m = re.search(r"\b(?:Total non-merge commits|Commits analysed|Total commits)[:\s*`]+([0-9]+)", text, re.I)
        if m: commits_count = int(m.group(1))

        # Check commit count from commits.txt if 0
        if commits_count == 0:
            cfile = os.path.join(REPO_ROOT, "Outputs", "Object History", "v4", obj, "commits.txt")
            if os.path.exists(cfile):
                with open(cfile) as cfh:
                    commits_count = len([l for l in cfh if l.strip()])

        # Source files
        src_files = []
        fn_file = os.path.join(REPO_ROOT, "Outputs", "Object History", "v4", obj, "functions.txt")
        if os.path.exists(fn_file):
            with open(fn_file) as fh_fn:
                for l in fh_fn:
                    l = l.strip()
                    if not l or l.startswith("#"): continue
                    parts = l.split("|")
                    if len(parts) >= 2:
                        src_files.append(parts[1].strip().split(":")[0].strip())
        src_files = sorted(list(set(src_files)))

        # Parse functions
        candidates = []
        for idx, line in enumerate(lines):
            if line.startswith("## "):
                title = line.lstrip("#").strip()
                clean = re.sub(r"[`*]", "", title).strip()
                clean_lower = clean.lower()
                if not any(clean_lower.startswith(x) or clean_lower == x for x in non_func_titles):
                    if not clean_lower.startswith("class:") and not clean_lower.startswith("1.") and not clean_lower.startswith("2.") and not clean_lower.startswith("3.") and not clean_lower.startswith("4.") and not clean_lower.startswith("5."):
                        candidates.append((2, idx, line, clean))
            elif line.startswith("### "):
                title = line.lstrip("#").strip()
                clean = re.sub(r"[`*]", "", title).strip()
                clean_lower = clean.lower()
                if not any(clean_lower.startswith(x) or clean_lower == x for x in [
                    "intent", "invariants", "invariants and contracts", "error conditions",
                    "evolution summary", "deferred", "implementation critique",
                    "test-writing notes", "relevant commits", "commit history",
                    "true authorship", "rename-chain", "files at head", "notable structural events",
                    "lock ordering", "perfcountertypes", "devicestate::empty() sentinel",
                    "4.1 diverged", "4.2 ungrounded", "4.3 overcautious", "1.1 commit",
                    "1.2 rename", "1.3 rename", "1.4 true", "diverged findings", "ungrounded code paths",
                    "overcautious findings"
                ]):
                    candidates.append((3, idx, line, clean))
                    
        h2_c = [c for c in candidates if c[0] == 2]
        h3_c = [c for c in candidates if c[0] == 3]
        
        chosen_candidates = h2_c if len(h2_c) >= len(h3_c) and len(h2_c) > 0 else h3_c
        if not chosen_candidates:
            chosen_candidates = candidates
            
        functions = []
        for i, (lvl, l_idx, raw_line, clean_title) in enumerate(chosen_candidates):
            start = l_idx
            end = chosen_candidates[i+1][1] if i+1 < len(chosen_candidates) else len(lines)
            fn_text = "\n".join(lines[start:end])
            
            tags = re.findall(r"\*\*(UNGROUNDED|DIVERGED|OVERCAUTIOUS|DEFECT|HAZARD|CONCERN|GAP|RISK|MISSING|CORRECT|SOUND|SATISFIES|OK)\*\*", fn_text)
            div_field = re.search(r"\*\*Divergence:\*\*\s*([A-Za-z0-9_]+)", fn_text)
            
            c_div = 0
            c_ung = 0
            c_over = 0
            c_other = 0
            
            if div_field:
                df = div_field.group(1).upper()
                if "DIVERGE" in df: c_div += 1
                
            for t in tags:
                tu = t.upper()
                if tu in ["DIVERGED", "DEFECT", "HAZARD"]: c_div += 1
                elif tu == "UNGROUNDED": c_ung += 1
                elif tu == "OVERCAUTIOUS": c_over += 1
                elif tu in ["CONCERN", "GAP", "RISK", "MISSING"]: c_other += 1
                
            status = "CLEAN"
            if c_div > 0: status = "DIVERGED"
            elif c_ung > 0: status = "UNGROUNDED"
            elif c_over > 0: status = "OVERCAUTIOUS"
            elif c_other > 0: status = "CONCERN"
            
            loc_match = re.findall(r"(?:src/mgr/[A-Za-z0-9_.]+(?:\.cc|\.h)?:\d+|[A-Za-z0-9_]+\.(?:cc|h):\d+|\.cc:\d+|\.h:\d+)", fn_text[:300])
            
            functions.append({
                "id": f"{obj}_{i+1}",
                "title": clean_title,
                "status": status,
                "counts": {
                    "diverged": c_div,
                    "ungrounded": c_ung,
                    "overcautious": c_over,
                    "concern": c_other
                },
                "locs": loc_match,
                "raw_markdown": fn_text
            })
            
        results.append({
            "object": obj,
            "head_sha": head_sha,
            "date": date_str,
            "commits": commits_count,
            "source_files": src_files,
            "function_count": len(functions),
            "functions": functions,
            "totals": {
                "diverged": sum(fn["counts"]["diverged"] for fn in functions),
                "ungrounded": sum(fn["counts"]["ungrounded"] for fn in functions),
                "overcautious": sum(fn["counts"]["overcautious"] for fn in functions),
                "concern": sum(fn["counts"]["concern"] for fn in functions),
                "clean": sum(1 for fn in functions if fn["status"] == "CLEAN"),
                "with_concerns": sum(1 for fn in functions if fn["status"] != "CLEAN")
            }
        })
        
    return results

if __name__ == "__main__":
    data = build_data()
    print("Objects parsed:", len(data))
    for d in data:
        t = d["totals"]
        print(f"{d['object']:28} | Funcs: {d['function_count']:2} | Div: {t['diverged']:2} | Ung: {t['ungrounded']:2} | Over: {t['overcautious']:2} | Clean: {t['clean']:2}")
    
    total_funcs = sum(d["function_count"] for d in data)
    total_div = sum(d["totals"]["diverged"] for d in data)
    total_ung = sum(d["totals"]["ungrounded"] for d in data)
    total_over = sum(d["totals"]["overcautious"] for d in data)
    total_clean = sum(d["totals"]["clean"] for d in data)
    print("="*60)
    print(f"Grand Total: {len(data)} Objects | {total_funcs} Functions")
    print(f"DIVERGED: {total_div} | UNGROUNDED: {total_ung} | OVERCAUTIOUS: {total_over} | CLEAN: {total_clean}")
    
    output_json = os.path.join(SCRIPT_DIR, "parsed_intents.json")
    with open(output_json, "w") as out:
        json.dump(data, out, indent=2)
    print(f"Saved {output_json}")
