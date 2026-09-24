import os, glob, re, json
try:
    import markdown
except ImportError:
    markdown = None

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(SCRIPT_DIR)

def load_source_files():
    sources = {}
    base_dir = "../ceph/src/mgr"
    if os.path.exists(base_dir):
        for f in glob.glob(os.path.join(base_dir, "*")):
            if os.path.isfile(f):
                fname = os.path.basename(f)
                try:
                    with open(f, "r", encoding="utf-8", errors="replace") as fh:
                        sources[fname] = fh.read()
                except Exception as e:
                    print(f"Error reading {f}: {e}")
    return sources

def parse_line_ranges(text, default_file=""):
    """
    Extract line numbers and ranges mentioned in critique/findings text.
    Returns a dict mapping filename -> list of [start, end] ranges.
    """
    findings_map = {}
    
    # Patterns to find:
    # 1. "Lines cc:52-58", "Lines h:27-28", "Line cc:131"
    # 2. "Gil.cc:28–50", "Gil.h:37–40", "src/mgr/Gil.cc:48"
    # 3. "Lines 239–242", "Line 48", "lines 45–49"
    # 4. "blame line 566", "blame lines 167–169"
    
    # File-specific mentions
    p_file_lines = re.findall(r'(?:(?:src/mgr/)?([A-Za-z0-9_]+\.(?:cc|h))|\b(cc|h))\s*[:]\s*(\d+)(?:\s*[-–—]\s*(\d+))?', text)
    for fl in p_file_lines:
        fname = fl[0] or fl[1]
        s_line = int(fl[2])
        e_line = int(fl[3]) if fl[3] else s_line
        
        # normalize filename
        if fname in ['cc', 'h']:
            if default_file:
                # replace extension on default_file base
                base = default_file.rsplit('.', 1)[0]
                fname = f"{base}.{fname}"
            else:
                fname = f".{fname}"
        
        findings_map.setdefault(fname, []).append([s_line, e_line])
        
    # Generic "Lines 123-145" or "Line 123"
    p_generic = re.findall(r'\b(?:Lines?|lines?|blame lines?)\s+(\d+)(?:\s*[-–—]\s*(\d+))?', text)
    for g in p_generic:
        s_line = int(g[0])
        e_line = int(g[1]) if g[1] else s_line
        # Ignore small numbers that might be commit counts or section numbers like "Line 1" or "Line 2" if not realistic
        target = default_file if default_file else "default"
        findings_map.setdefault(target, []).append([s_line, e_line])
        
    return findings_map

def build_dataset():
    files = sorted(glob.glob(os.path.join(REPO_ROOT, "Outputs", "Intents", "*-intent.md")))
    sources = load_source_files()
    
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
        
        # Metadata
        head_sha = "8681fa6ebac230f86eb445bf57095c63e7f1abcc"
        m = re.search(r"\b(?:HEAD SHA|Corpus HEAD)[:\s*`]+([a-f0-9]{8,40})", text, re.I)
        if m: head_sha = m.group(1)

        date_str = ""
        m = re.search(r"\b(?:Generated|Assessment date|Corpus collected at)[:\s*`]+([^\n\r`]+)", text, re.I)
        if m: date_str = m.group(1).strip()
        
        commits_count = 0
        m = re.search(r"\b(?:Total non-merge commits|Commits analysed|Total commits)[:\s*`]+([0-9]+)", text, re.I)
        if m: commits_count = int(m.group(1))

        if commits_count == 0:
            cfile = os.path.join(REPO_ROOT, "Outputs", "Object History", "v4", obj, "commits.txt")
            if os.path.exists(cfile):
                with open(cfile) as cfh:
                    commits_count = len([l for l in cfh if l.strip()])

        # Source files for this object
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
        if not src_files:
            if f"{obj}.cc" in sources: src_files.append(f"src/mgr/{obj}.cc")
            if f"{obj}.h" in sources: src_files.append(f"src/mgr/{obj}.h")

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
            
        overview_end = chosen_candidates[0][1] if chosen_candidates else len(lines)
        overview_text = "\n".join(lines[:overview_end])
        
        overview_html = ""
        if markdown:
            overview_html = markdown.markdown(overview_text, extensions=["fenced_code", "tables"])

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
            
            loc_match = re.findall(r"(?:src/mgr/[A-Za-z0-9_.]+(?:\.cc|\.h)?:\d+|[A-Za-z0-9_]+\.(?:cc|h):\d+|\.cc:\d+|\.h:\d+)", fn_text[:400])
            
            # Extract precise declaration/implementation range
            primary_file = ""
            primary_line = 0
            for lm in loc_match:
                if ":" in lm:
                    fpart, lpart = lm.rsplit(":", 1)
                    if lpart.isdigit():
                        primary_line = int(lpart)
                        primary_file = fpart
                        break
            
            # Extract concern lines from critique
            critique_text = ""
            m_crit = re.search(r"(?:###+\s*Implementation critique|\*\*Implementation critique[^\n]*\*\*)[^\n]*\n(.*?)(?=\n###|\n##|\Z)", fn_text, re.S)
            if m_crit:
                critique_text = m_crit.group(1)
            else:
                critique_text = fn_text
                
            concern_lines_map = parse_line_ranges(critique_text, default_file=primary_file or f"{obj}.cc")

            # Markdown rendering
            fn_html = ""
            if markdown:
                fn_html = markdown.markdown(fn_text, extensions=["fenced_code", "tables"])
            
            functions.append({
                "id": f"{obj}_fn_{i+1}",
                "title": clean_title,
                "status": status,
                "counts": {
                    "diverged": c_div,
                    "ungrounded": c_ung,
                    "overcautious": c_over,
                    "concern": c_other
                },
                "locs": loc_match,
                "primary_file": primary_file,
                "primary_line": primary_line,
                "concern_lines": concern_lines_map,
                "raw_markdown": fn_text,
                "html": fn_html
            })
            
        obj_sources = {}
        for sf in src_files:
            sf_basename = os.path.basename(sf)
            if sf_basename in sources:
                obj_sources[sf] = sources[sf_basename]

        results.append({
            "object": obj,
            "head_sha": head_sha,
            "date": date_str,
            "commits": commits_count,
            "source_files": src_files,
            "sources": obj_sources,
            "overview_html": overview_html,
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
    dataset = build_dataset()
    output_json = os.path.join(SCRIPT_DIR, "dataset.json")
    with open(output_json, "w", encoding="utf-8") as out:
        json.dump(dataset, out)
    print(f"Updated {output_json} with precise concern ranges.")
