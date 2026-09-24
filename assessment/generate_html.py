import os, glob, re, json

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(SCRIPT_DIR)

HTML_TEMPLATE = r"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Ceph Manager (mgr) — Intent Artefacts & Assessment Explorer</title>
<style>
  :root {
    --bg-main: #0d1117;
    --bg-card: #161b22;
    --bg-card-hover: #1c2128;
    --bg-subtle: #21262d;
    --border: #30363d;
    --border-light: #484f58;
    --text-main: #c9d1d9;
    --text-bright: #f0f6fc;
    --text-muted: #8b949e;
    
    --color-clean: #238636;
    --color-clean-bg: rgba(35, 134, 54, 0.15);
    --color-clean-border: #2ea043;
    
    --color-diverged: #da3633;
    --color-diverged-bg: rgba(218, 54, 51, 0.15);
    --color-diverged-border: #f85149;
    
    --color-ungrounded: #d29922;
    --color-ungrounded-bg: rgba(210, 153, 34, 0.15);
    --color-ungrounded-border: #e3b341;
    
    --color-overcautious: #a371f7;
    --color-overcautious-bg: rgba(163, 113, 247, 0.15);
    --color-overcautious-border: #bc8cff;
    
    --color-concern: #db6d28;
    --color-concern-bg: rgba(219, 109, 40, 0.15);
    --color-concern-border: #f0883e;

    --color-accent: #58a6ff;
    --color-accent-bg: rgba(88, 166, 255, 0.1);
  }

  * { box-sizing: border-box; margin: 0; padding: 0; }
  body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    background-color: var(--bg-main);
    color: var(--text-main);
    line-height: 1.5;
    font-size: 14px;
    height: 100vh;
    overflow: hidden;
    display: flex;
    flex-direction: column;
  }

  /* Top Navigation Bar */
  header {
    background-color: var(--bg-card);
    border-bottom: 1px solid var(--border);
    padding: 10px 24px;
    display: flex;
    align-items: center;
    justify-content: space-between;
    flex-shrink: 0;
    z-index: 100;
  }
  .header-left {
    display: flex;
    align-items: center;
    gap: 16px;
  }
  .header-title {
    font-size: 16px;
    font-weight: 700;
    color: var(--text-bright);
    display: flex;
    align-items: center;
    gap: 8px;
    cursor: pointer;
  }
  .header-title .logo {
    background: linear-gradient(135deg, #e34c26, #f06529);
    color: #fff;
    padding: 2px 8px;
    border-radius: 4px;
    font-size: 11px;
    font-weight: 800;
    letter-spacing: 0.5px;
  }
  .breadcrumbs {
    display: flex;
    align-items: center;
    gap: 8px;
    font-size: 13px;
    color: var(--text-muted);
  }
  .breadcrumb-item {
    cursor: pointer;
    color: var(--color-accent);
  }
  .breadcrumb-item:hover { text-decoration: underline; }
  .breadcrumb-sep { color: var(--text-muted); }
  .breadcrumb-current { color: var(--text-bright); font-weight: 600; }

  .header-stats {
    display: flex;
    align-items: center;
    gap: 12px;
  }
  .stat-badge {
    padding: 3px 10px;
    border-radius: 20px;
    font-size: 12px;
    font-weight: 600;
    display: inline-flex;
    align-items: center;
    gap: 6px;
    border: 1px solid transparent;
  }
  .badge-diverged { background: var(--color-diverged-bg); color: var(--color-diverged-border); border-color: var(--color-diverged); }
  .badge-ungrounded { background: var(--color-ungrounded-bg); color: var(--color-ungrounded-border); border-color: var(--color-ungrounded); }
  .badge-overcautious { background: var(--color-overcautious-bg); color: var(--color-overcautious-border); border-color: var(--color-overcautious); }
  .badge-clean { background: var(--color-clean-bg); color: var(--color-clean-border); border-color: var(--color-clean); }
  .badge-neutral { background: var(--bg-subtle); color: var(--text-muted); border-color: var(--border); }

  /* Main Container Layout */
  .main-layout {
    display: flex;
    flex: 1;
    overflow: hidden;
  }

  /* Sidebar */
  sidebar {
    width: 280px;
    background-color: var(--bg-card);
    border-right: 1px solid var(--border);
    display: flex;
    flex-direction: column;
    flex-shrink: 0;
  }
  .sidebar-header {
    padding: 12px 16px;
    border-bottom: 1px solid var(--border);
    font-size: 12px;
    font-weight: 600;
    color: var(--text-muted);
    text-transform: uppercase;
    letter-spacing: 0.5px;
    display: flex;
    justify-content: space-between;
    align-items: center;
  }
  .sidebar-search {
    padding: 8px 16px;
    border-bottom: 1px solid var(--border);
  }
  .search-input {
    width: 100%;
    background-color: var(--bg-main);
    border: 1px solid var(--border);
    border-radius: 6px;
    padding: 6px 10px;
    color: var(--text-bright);
    font-size: 13px;
    outline: none;
  }
  .search-input:focus {
    border-color: var(--color-accent);
  }
  .sidebar-list {
    flex: 1;
    overflow-y: auto;
    padding: 6px 0;
  }
  .sidebar-item {
    padding: 8px 16px;
    display: flex;
    align-items: center;
    justify-content: space-between;
    cursor: pointer;
    transition: background 0.15s;
    font-size: 13px;
  }
  .sidebar-item:hover {
    background-color: var(--bg-subtle);
  }
  .sidebar-item.active {
    background-color: var(--color-accent-bg);
    border-left: 3px solid var(--color-accent);
    color: var(--text-bright);
    font-weight: 600;
  }
  .sidebar-item-name {
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .sidebar-pills {
    display: flex;
    gap: 4px;
    flex-shrink: 0;
  }
  .pill-mini {
    font-size: 10px;
    padding: 1px 5px;
    border-radius: 10px;
    font-weight: 700;
  }

  /* Content Views Area */
  main {
    flex: 1;
    overflow-y: auto;
    background-color: var(--bg-main);
    display: flex;
    flex-direction: column;
  }

  .view-container {
    padding: 24px 32px;
    width: 100%;
    margin: 0 auto;
    flex: 1;
  }

  /* View Header */
  .page-title-row {
    display: flex;
    justify-content: space-between;
    align-items: flex-start;
    margin-bottom: 20px;
    padding-bottom: 16px;
    border-bottom: 1px solid var(--border);
  }
  .page-title {
    font-size: 22px;
    font-weight: 700;
    color: var(--text-bright);
    margin-bottom: 6px;
    display: flex;
    align-items: center;
    gap: 12px;
  }
  .page-subtitle {
    font-size: 13px;
    color: var(--text-muted);
  }

  /* Cards & Grids */
  .metrics-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
    gap: 16px;
    margin-bottom: 24px;
  }
  .metric-card {
    background-color: var(--bg-card);
    border: 1px solid var(--border);
    border-radius: 8px;
    padding: 16px;
    display: flex;
    flex-direction: column;
    gap: 6px;
  }
  .metric-card-title {
    font-size: 12px;
    font-weight: 600;
    color: var(--text-muted);
    text-transform: uppercase;
    letter-spacing: 0.5px;
  }
  .metric-card-value {
    font-size: 28px;
    font-weight: 800;
    color: var(--text-bright);
    display: flex;
    align-items: baseline;
    gap: 8px;
  }

  /* Filter / Control Bar */
  .filter-bar {
    display: flex;
    gap: 10px;
    align-items: center;
    margin-bottom: 16px;
    flex-wrap: wrap;
  }
  .filter-btn {
    background-color: var(--bg-card);
    border: 1px solid var(--border);
    color: var(--text-main);
    padding: 6px 14px;
    border-radius: 6px;
    font-size: 12px;
    font-weight: 600;
    cursor: pointer;
    transition: all 0.15s;
    display: inline-flex;
    align-items: center;
    gap: 6px;
  }
  .filter-btn:hover { background-color: var(--bg-subtle); color: var(--text-bright); }
  .filter-btn.active {
    background-color: var(--color-accent-bg);
    border-color: var(--color-accent);
    color: var(--color-accent);
  }

  /* Table Styles */
  .styled-table {
    width: 100%;
    border-collapse: separate;
    border-spacing: 0;
    background-color: var(--bg-card);
    border: 1px solid var(--border);
    border-radius: 8px;
    overflow: hidden;
    margin-bottom: 24px;
  }
  .styled-table th {
    background-color: var(--bg-subtle);
    padding: 10px 16px;
    text-align: left;
    font-size: 12px;
    font-weight: 600;
    color: var(--text-muted);
    border-bottom: 1px solid var(--border);
    text-transform: uppercase;
    letter-spacing: 0.5px;
  }
  .styled-table td {
    padding: 12px 16px;
    border-bottom: 1px solid var(--border);
    font-size: 13px;
    vertical-align: middle;
  }
  .styled-table tr:last-child td { border-bottom: none; }
  .styled-table tr:hover td { background-color: var(--bg-card-hover); }
  .table-link {
    color: var(--color-accent);
    font-weight: 600;
    cursor: pointer;
    text-decoration: none;
  }
  .table-link:hover { text-decoration: underline; }

  /* Function Card / List */
  .func-list {
    display: flex;
    flex-direction: column;
    gap: 12px;
    margin-bottom: 40px;
  }
  .func-card {
    background-color: var(--bg-card);
    border: 1px solid var(--border);
    border-radius: 8px;
    padding: 16px 20px;
    cursor: pointer;
    transition: all 0.15s;
    display: flex;
    justify-content: space-between;
    align-items: center;
  }
  .func-card:hover {
    background-color: var(--bg-card-hover);
    border-color: var(--border-light);
    transform: translateY(-1px);
  }
  .func-card-left {
    display: flex;
    flex-direction: column;
    gap: 4px;
  }
  .func-card-title {
    font-size: 15px;
    font-weight: 600;
    color: var(--text-bright);
    font-family: ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, monospace;
    display: flex;
    align-items: center;
    gap: 10px;
  }
  .func-card-subtitle {
    font-size: 12px;
    color: var(--text-muted);
    display: flex;
    gap: 12px;
  }

  /* Collapsible Overview Box */
  .collapsible-box {
    background-color: var(--bg-card);
    border: 1px solid var(--border);
    border-radius: 8px;
    overflow: hidden;
    margin-bottom: 24px;
  }
  .collapsible-header {
    background-color: var(--bg-subtle);
    padding: 10px 16px;
    font-size: 13px;
    font-weight: 600;
    color: var(--text-bright);
    display: flex;
    justify-content: space-between;
    align-items: center;
    cursor: pointer;
    user-select: none;
  }
  .collapsible-header:hover {
    background-color: var(--bg-card-hover);
  }
  .collapsible-toggle-icon {
    font-size: 12px;
    color: var(--text-muted);
    transition: transform 0.2s;
  }
  .collapsible-body {
    padding: 20px;
    font-size: 14px;
    color: var(--text-main);
    line-height: 1.7;
    max-height: 260px;
    overflow-y: auto;
    border-top: 1px solid var(--border);
  }

  /* Function Detail View Draggable Splitter Layout */
  .fn-split-container {
    display: flex;
    width: 100%;
    gap: 0;
    position: relative;
    user-select: auto;
  }

  .fn-pane {
    min-width: 250px;
    overflow: hidden;
    display: flex;
    flex-direction: column;
  }
  .fn-pane-left {
    width: 50%;
  }
  .fn-pane-right {
    flex: 1;
    min-width: 250px;
  }

  .fn-splitter {
    width: 12px;
    margin: 0 -2px;
    cursor: col-resize;
    position: relative;
    z-index: 50;
    display: flex;
    align-items: center;
    justify-content: center;
    user-select: none;
    flex-shrink: 0;
  }
  .fn-splitter::after {
    content: "";
    width: 4px;
    height: 48px;
    background-color: var(--border);
    border-radius: 2px;
    transition: all 0.15s;
  }
  .fn-splitter:hover::after, .fn-splitter.dragging::after {
    background-color: var(--color-accent);
    width: 6px;
    height: 100%;
  }

  .panel-box {
    background-color: var(--bg-card);
    border: 1px solid var(--border);
    border-radius: 8px;
    overflow: hidden;
    display: flex;
    flex-direction: column;
    height: 100%;
  }
  .panel-box-header {
    background-color: var(--bg-subtle);
    padding: 10px 16px;
    border-bottom: 1px solid var(--border);
    font-size: 13px;
    font-weight: 600;
    color: var(--text-bright);
    display: flex;
    justify-content: space-between;
    align-items: center;
    flex-shrink: 0;
  }

  .prose {
    padding: 20px;
    font-size: 14px;
    color: var(--text-main);
    line-height: 1.7;
    overflow-y: auto;
    max-height: 780px;
  }
  .prose h1, .prose h2, .prose h3, .prose h4 {
    color: var(--text-bright);
    margin-top: 20px;
    margin-bottom: 10px;
  }
  .prose h1:first-child, .prose h2:first-child, .prose h3:first-child { margin-top: 0; }
  .prose p { margin-bottom: 14px; }
  .prose ul, .prose ol { margin-bottom: 14px; padding-left: 24px; }
  .prose li { margin-bottom: 4px; }
  .prose code {
    background-color: var(--bg-subtle);
    padding: 2px 6px;
    border-radius: 4px;
    font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
    font-size: 12px;
    color: #f0883e;
  }
  .prose pre {
    background-color: var(--bg-main);
    border: 1px solid var(--border);
    border-radius: 6px;
    padding: 14px;
    margin-bottom: 16px;
    overflow-x: auto;
  }
  .prose pre code {
    background: none;
    padding: 0;
    color: var(--text-main);
    font-size: 12px;
  }
  .prose blockquote {
    border-left: 3px solid var(--color-accent);
    padding-left: 14px;
    color: var(--text-muted);
    margin-bottom: 14px;
    font-style: italic;
  }
  .prose table {
    width: 100%;
    border-collapse: collapse;
    margin-bottom: 16px;
  }
  .prose th, .prose td {
    border: 1px solid var(--border);
    padding: 6px 10px;
    font-size: 13px;
  }
  .prose th { background-color: var(--bg-subtle); color: var(--text-bright); }

  /* Code Viewer */
  .code-container {
    background-color: var(--bg-main);
    font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
    font-size: 12px;
    overflow: auto;
    max-height: 740px;
    flex: 1;
  }
  .code-table {
    width: 100%;
    border-collapse: collapse;
  }
  .code-line {
    display: flex;
    line-height: 1.6;
    transition: background-color 0.15s;
  }
  .code-line:hover {
    background-color: var(--bg-subtle);
  }
  
  /* Highlighting classes */
  .code-line.highlight-func {
    background-color: rgba(88, 166, 255, 0.12);
    border-left: 3px solid var(--color-accent);
  }
  .code-line.highlight-concern-diverged {
    background-color: rgba(218, 54, 51, 0.22) !important;
    border-left: 3px solid var(--color-diverged-border) !important;
  }
  .code-line.highlight-concern-ungrounded {
    background-color: rgba(210, 153, 34, 0.22) !important;
    border-left: 3px solid var(--color-ungrounded-border) !important;
  }
  .code-line.highlight-concern-overcautious {
    background-color: rgba(163, 113, 247, 0.22) !important;
    border-left: 3px solid var(--color-overcautious-border) !important;
  }
  .code-line.highlight-concern-general {
    background-color: rgba(219, 109, 40, 0.22) !important;
    border-left: 3px solid var(--color-concern-border) !important;
  }

  .line-num {
    width: 52px;
    text-align: right;
    padding-right: 12px;
    color: var(--text-muted);
    user-select: none;
    border-right: 1px solid var(--border);
    flex-shrink: 0;
  }
  .line-text {
    padding-left: 14px;
    white-space: pre;
    color: #e6edf3;
    flex: 1;
  }
  .code-file-select {
    background-color: var(--bg-main);
    border: 1px solid var(--border);
    color: var(--text-bright);
    padding: 4px 8px;
    border-radius: 4px;
    font-size: 12px;
    outline: none;
  }

  .code-legend {
    display: flex;
    gap: 12px;
    align-items: center;
    padding: 6px 16px;
    background-color: var(--bg-subtle);
    border-bottom: 1px solid var(--border);
    font-size: 11px;
    color: var(--text-muted);
    flex-shrink: 0;
    flex-wrap: wrap;
  }
  .legend-item {
    display: inline-flex;
    align-items: center;
    gap: 5px;
  }
  .legend-box {
    width: 12px;
    height: 12px;
    border-radius: 2px;
    border: 1px solid;
  }

  /* Scrollbar */
  ::-webkit-scrollbar { width: 8px; height: 8px; }
  ::-webkit-scrollbar-track { background: var(--bg-main); }
  ::-webkit-scrollbar-thumb { background: var(--border); border-radius: 4px; }
  ::-webkit-scrollbar-thumb:hover { background: var(--border-light); }
</style>
</head>
<body>

<header>
  <div class="header-left">
    <div class="header-title" onclick="navToHome()">
      <span class="logo">CEPH MGR</span>
      <span>Intent & Assessment Explorer</span>
    </div>
    <div class="breadcrumbs" id="breadcrumbs">
      <span class="breadcrumb-current">Home Overview</span>
    </div>
  </div>
  <div class="header-stats" id="header-stats"></div>
</header>

<div class="main-layout">
  <sidebar>
    <div class="sidebar-header">
      <span>Objects (<span id="obj-count">0</span>)</span>
      <span id="total-fn-count" style="font-size: 11px;">0 funcs</span>
    </div>
    <div class="sidebar-search">
      <input type="text" id="obj-search" class="search-input" placeholder="Search objects..." oninput="filterSidebar()">
    </div>
    <div class="sidebar-list" id="sidebar-list"></div>
  </sidebar>

  <main id="main-content">
    <div id="view-home" class="view-container"></div>
    <div id="view-object" class="view-container" style="display: none;"></div>
    <div id="view-function" class="view-container" style="display: none;"></div>
  </main>
</div>

<script>
// DATA INJECTED BY BUILD SCRIPT
const DATA = %%DATA_JSON%%;

let currentObject = null;
let currentFunction = null;
let statusFilter = 'ALL';
let codeActiveFile = '';

// Saved split pane width ratio (percentage)
let splitRatioLeft = parseFloat(localStorage.getItem('ceph_mgr_split_ratio') || '50');

// Initialize
window.addEventListener('DOMContentLoaded', () => {
  renderSidebar();
  renderHomeStats();
  renderHomeView();
  
  // Handle URL hash routing
  window.addEventListener('hashchange', handleRoute);
  handleRoute();
});

function handleRoute() {
  const hash = window.location.hash.replace(/^#\/?/, '');
  if (!hash) {
    navToHome(false);
    return;
  }
  const parts = hash.split('/');
  if (parts.length === 1 && parts[0]) {
    const obj = DATA.find(d => d.object === parts[0]);
    if (obj) navToObject(obj.object, false);
    else navToHome(false);
  } else if (parts.length >= 2) {
    const obj = DATA.find(d => d.object === parts[0]);
    if (obj) {
      const fn = obj.functions.find(f => f.id === parts[1]);
      if (fn) navToFunction(obj.object, fn.id, false);
      else navToObject(obj.object, false);
    } else {
      navToHome(false);
    }
  }
}

function updateUrl(hash) {
  window.location.hash = hash;
}

function renderHomeStats() {
  const totalObjs = DATA.length;
  const totalFuncs = DATA.reduce((acc, d) => acc + d.function_count, 0);
  const totalDiv = DATA.reduce((acc, d) => acc + d.totals.diverged, 0);
  const totalUng = DATA.reduce((acc, d) => acc + d.totals.ungrounded, 0);
  const totalOver = DATA.reduce((acc, d) => acc + d.totals.overcautious, 0);
  const totalClean = DATA.reduce((acc, d) => acc + d.totals.clean, 0);

  document.getElementById('obj-count').innerText = totalObjs;
  document.getElementById('total-fn-count').innerText = `${totalFuncs} functions`;

  const statsEl = document.getElementById('header-stats');
  statsEl.innerHTML = `
    <span class="stat-badge badge-diverged" title="Diverged from historical design/commits">⚡ ${totalDiv} Diverged</span>
    <span class="stat-badge badge-ungrounded" title="Ungrounded code paths / missing invariants">⚠️ ${totalUng} Ungrounded</span>
    <span class="stat-badge badge-overcautious" title="Overcautious / redundant guards">🛡️ ${totalOver} Overcautious</span>
    <span class="stat-badge badge-clean" title="Clean / Satisfies specifications">✓ ${totalClean} Clean</span>
  `;
}

function renderSidebar() {
  const listEl = document.getElementById('sidebar-list');
  const search = (document.getElementById('obj-search')?.value || '').toLowerCase();
  
  let html = '';
  DATA.forEach(d => {
    if (search && !d.object.toLowerCase().includes(search)) return;
    const isActive = currentObject && currentObject.object === d.object && !currentFunction;
    
    let pills = '';
    if (d.totals.diverged > 0) pills += `<span class="pill-mini badge-diverged">${d.totals.diverged}</span>`;
    if (d.totals.ungrounded > 0) pills += `<span class="pill-mini badge-ungrounded">${d.totals.ungrounded}</span>`;
    if (d.totals.overcautious > 0) pills += `<span class="pill-mini badge-overcautious">${d.totals.overcautious}</span>`;
    if (!pills) pills = `<span class="pill-mini badge-clean">${d.function_count}</span>`;

    html += `
      <div class="sidebar-item ${isActive ? 'active' : ''}" onclick="navToObject('${d.object}')">
        <span class="sidebar-item-name" title="${d.object}">${d.object}</span>
        <div class="sidebar-pills">${pills}</div>
      </div>
    `;
  });
  listEl.innerHTML = html;
}

function filterSidebar() {
  renderSidebar();
}

function navToHome(updateHash = true) {
  currentObject = null;
  currentFunction = null;
  if (updateHash) updateUrl('');
  
  document.getElementById('breadcrumbs').innerHTML = `<span class="breadcrumb-current">Home Overview</span>`;
  document.getElementById('view-home').style.display = 'block';
  document.getElementById('view-object').style.display = 'none';
  document.getElementById('view-function').style.display = 'none';
  renderSidebar();
  renderHomeView();
}

function navToObject(objName, updateHash = true) {
  const obj = DATA.find(d => d.object === objName);
  if (!obj) return;
  currentObject = obj;
  currentFunction = null;
  statusFilter = 'ALL';
  if (updateHash) updateUrl(obj.object);

  document.getElementById('breadcrumbs').innerHTML = `
    <span class="breadcrumb-item" onclick="navToHome()">Home</span>
    <span class="breadcrumb-sep">/</span>
    <span class="breadcrumb-current">${obj.object}</span>
  `;
  document.getElementById('view-home').style.display = 'none';
  document.getElementById('view-object').style.display = 'block';
  document.getElementById('view-function').style.display = 'none';
  renderSidebar();
  renderObjectView();
}

function navToFunction(objName, fnId, updateHash = true) {
  const obj = DATA.find(d => d.object === objName);
  if (!obj) return;
  const fn = obj.functions.find(f => f.id === fnId);
  if (!fn) return;
  currentObject = obj;
  currentFunction = fn;
  if (updateHash) updateUrl(`${obj.object}/${fn.id}`);

  document.getElementById('breadcrumbs').innerHTML = `
    <span class="breadcrumb-item" onclick="navToHome()">Home</span>
    <span class="breadcrumb-sep">/</span>
    <span class="breadcrumb-item" onclick="navToObject('${obj.object}')">${obj.object}</span>
    <span class="breadcrumb-sep">/</span>
    <span class="breadcrumb-current">${escapeHtml(fn.title)}</span>
  `;
  document.getElementById('view-home').style.display = 'none';
  document.getElementById('view-object').style.display = 'none';
  document.getElementById('view-function').style.display = 'block';
  renderSidebar();
  renderFunctionView();
}

function renderHomeView() {
  const totalObjs = DATA.length;
  const totalFuncs = DATA.reduce((acc, d) => acc + d.function_count, 0);
  const totalDiv = DATA.reduce((acc, d) => acc + d.totals.diverged, 0);
  const totalUng = DATA.reduce((acc, d) => acc + d.totals.ungrounded, 0);
  const totalOver = DATA.reduce((acc, d) => acc + d.totals.overcautious, 0);
  const totalCommits = DATA.reduce((acc, d) => acc + d.commits, 0);

  let html = `
    <div class="page-title-row">
      <div>
        <h1 class="page-title">Ceph Manager (mgr) Assessment Overview</h1>
        <p class="page-subtitle">Historical intent reconstruction & divergence audit across ${totalObjs} core daemon objects</p>
      </div>
      <div style="font-size: 12px; color: var(--text-muted); text-align: right;">
        <div><strong>Corpus HEAD:</strong> <code>8681fa6e</code></div>
        <div><strong>Total Commits Analysed:</strong> ${totalCommits}</div>
      </div>
    </div>

    <div class="metrics-grid">
      <div class="metric-card">
        <span class="metric-card-title">Audited Objects</span>
        <span class="metric-card-value">${totalObjs}</span>
      </div>
      <div class="metric-card">
        <span class="metric-card-title">Total Functions</span>
        <span class="metric-card-value">${totalFuncs}</span>
      </div>
      <div class="metric-card" style="border-color: var(--color-diverged);">
        <span class="metric-card-title" style="color: var(--color-diverged-border);">Diverged Findings</span>
        <span class="metric-card-value" style="color: var(--color-diverged-border);">${totalDiv}</span>
      </div>
      <div class="metric-card" style="border-color: var(--color-ungrounded);">
        <span class="metric-card-title" style="color: var(--color-ungrounded-border);">Ungrounded Invariants</span>
        <span class="metric-card-value" style="color: var(--color-ungrounded-border);">${totalUng}</span>
      </div>
      <div class="metric-card" style="border-color: var(--color-overcautious);">
        <span class="metric-card-title" style="color: var(--color-overcautious-border);">Overcautious Guards</span>
        <span class="metric-card-value" style="color: var(--color-overcautious-border);">${totalOver}</span>
      </div>
    </div>

    <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 12px;">
      <h2 style="font-size: 16px; font-weight: 700; color: var(--text-bright);">All Objects & Concern Breakdown</h2>
      <input type="text" id="table-search" class="search-input" style="width: 250px;" placeholder="Filter objects..." oninput="filterHomeTable()">
    </div>

    <table class="styled-table" id="objects-table">
      <thead>
        <tr>
          <th>Object / Subsystem</th>
          <th>Source Files</th>
          <th style="text-align: right;">Commits</th>
          <th style="text-align: right;">Functions</th>
          <th style="text-align: right;">Diverged</th>
          <th style="text-align: right;">Ungrounded</th>
          <th style="text-align: right;">Overcautious</th>
          <th style="text-align: right;">Clean</th>
          <th>Health Status</th>
        </tr>
      </thead>
      <tbody>
  `;

  DATA.forEach(d => {
    const healthBadge = d.totals.diverged > 0 
      ? `<span class="stat-badge badge-diverged">Diverged</span>`
      : (d.totals.ungrounded > 0 
        ? `<span class="stat-badge badge-ungrounded">Ungrounded</span>`
        : (d.totals.overcautious > 0 
          ? `<span class="stat-badge badge-overcautious">Overcautious</span>`
          : `<span class="stat-badge badge-clean">Clean</span>`));

    const filesStr = d.source_files.map(sf => `<code>${sf.replace('src/mgr/', '')}</code>`).join(' ');

    html += `
      <tr class="obj-table-row" data-name="${d.object.toLowerCase()}">
        <td>
          <a class="table-link" onclick="navToObject('${d.object}')" style="font-size: 14px;"><strong>${d.object}</strong></a>
        </td>
        <td>${filesStr || '<span style="color: var(--text-muted);">-</span>'}</td>
        <td style="text-align: right; color: var(--text-muted); font-weight: 600;">${d.commits}</td>
        <td style="text-align: right; font-weight: 600;">${d.function_count}</td>
        <td style="text-align: right; font-weight: 700; color: ${d.totals.diverged ? 'var(--color-diverged-border)' : 'var(--text-muted)'};">${d.totals.diverged || '-'}</td>
        <td style="text-align: right; font-weight: 700; color: ${d.totals.ungrounded ? 'var(--color-ungrounded-border)' : 'var(--text-muted)'};">${d.totals.ungrounded || '-'}</td>
        <td style="text-align: right; font-weight: 700; color: ${d.totals.overcautious ? 'var(--color-overcautious-border)' : 'var(--text-muted)'};">${d.totals.overcautious || '-'}</td>
        <td style="text-align: right; font-weight: 700; color: ${d.totals.clean ? 'var(--color-clean-border)' : 'var(--text-muted)'};">${d.totals.clean}</td>
        <td>${healthBadge}</td>
      </tr>
    `;
  });

  html += `
      </tbody>
    </table>
  `;

  document.getElementById('view-home').innerHTML = html;
}

function filterHomeTable() {
  const val = (document.getElementById('table-search')?.value || '').toLowerCase();
  const rows = document.querySelectorAll('.obj-table-row');
  rows.forEach(r => {
    const name = r.getAttribute('data-name');
    r.style.display = name.includes(val) ? '' : 'none';
  });
}

function toggleOverviewCollapse(id) {
  const body = document.getElementById(id);
  const icon = document.getElementById(id + '-icon');
  if (!body) return;
  if (body.style.display === 'none') {
    body.style.display = 'block';
    if (icon) icon.innerText = '▲';
  } else {
    body.style.display = 'none';
    if (icon) icon.innerText = '▼';
  }
}

function renderObjectView() {
  if (!currentObject) return;
  const d = currentObject;

  let filteredFuncs = d.functions;
  if (statusFilter !== 'ALL') {
    filteredFuncs = d.functions.filter(f => f.status === statusFilter);
  }

  const filesStr = d.source_files.map(sf => `<code style="font-size: 12px; padding: 3px 6px;">${sf}</code>`).join(' ');

  let html = `
    <div class="page-title-row">
      <div>
        <h1 class="page-title">
          <span>${d.object}</span>
          <span style="font-size: 14px; font-weight: 400; color: var(--text-muted);">(${d.function_count} functions)</span>
        </h1>
        <div style="margin-top: 6px; display: flex; gap: 8px; align-items: center; flex-wrap: wrap;">
          <span style="color: var(--text-muted); font-size: 13px;">Source:</span> ${filesStr}
        </div>
      </div>
      <div style="display: flex; gap: 8px;">
        <button class="filter-btn" onclick="navToHome()">← Back to Overview</button>
      </div>
    </div>

    <div class="metrics-grid">
      <div class="metric-card">
        <span class="metric-card-title">Commits Analysed</span>
        <span class="metric-card-value">${d.commits}</span>
      </div>
      <div class="metric-card" style="border-color: var(--color-diverged);">
        <span class="metric-card-title" style="color: var(--color-diverged-border);">Diverged</span>
        <span class="metric-card-value" style="color: var(--color-diverged-border);">${d.totals.diverged}</span>
      </div>
      <div class="metric-card" style="border-color: var(--color-ungrounded);">
        <span class="metric-card-title" style="color: var(--color-ungrounded-border);">Ungrounded</span>
        <span class="metric-card-value" style="color: var(--color-ungrounded-border);">${d.totals.ungrounded}</span>
      </div>
      <div class="metric-card" style="border-color: var(--color-overcautious);">
        <span class="metric-card-title" style="color: var(--color-overcautious-border);">Overcautious</span>
        <span class="metric-card-value" style="color: var(--color-overcautious-border);">${d.totals.overcautious}</span>
      </div>
      <div class="metric-card" style="border-color: var(--color-clean);">
        <span class="metric-card-title" style="color: var(--color-clean-border);">Clean Functions</span>
        <span class="metric-card-value" style="color: var(--color-clean-border);">${d.totals.clean}</span>
      </div>
    </div>
  `;

  if (d.overview_html) {
    html += `
      <div class="collapsible-box">
        <div class="collapsible-header" onclick="toggleOverviewCollapse('obj-overview-body')">
          <span>Design Context & Subsystem Overview</span>
          <span class="collapsible-toggle-icon" id="obj-overview-body-icon">▲</span>
        </div>
        <div class="collapsible-body prose" id="obj-overview-body">
          ${d.overview_html}
        </div>
      </div>
    `;
  }

  html += `
    <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 14px;">
      <div class="filter-bar" style="margin-bottom: 0;">
        <span style="font-size: 13px; font-weight: 600; color: var(--text-muted); margin-right: 4px;">Filter Status:</span>
        <button class="filter-btn ${statusFilter === 'ALL' ? 'active' : ''}" onclick="setObjFilter('ALL')">All (${d.functions.length})</button>
        <button class="filter-btn ${statusFilter === 'DIVERGED' ? 'active' : ''}" onclick="setObjFilter('DIVERGED')">⚡ Diverged (${d.functions.filter(f => f.status === 'DIVERGED').length})</button>
        <button class="filter-btn ${statusFilter === 'UNGROUNDED' ? 'active' : ''}" onclick="setObjFilter('UNGROUNDED')">⚠️ Ungrounded (${d.functions.filter(f => f.status === 'UNGROUNDED').length})</button>
        <button class="filter-btn ${statusFilter === 'OVERCAUTIOUS' ? 'active' : ''}" onclick="setObjFilter('OVERCAUTIOUS')">🛡️ Overcautious (${d.functions.filter(f => f.status === 'OVERCAUTIOUS').length})</button>
        <button class="filter-btn ${statusFilter === 'CLEAN' ? 'active' : ''}" onclick="setObjFilter('CLEAN')">✓ Clean (${d.functions.filter(f => f.status === 'CLEAN').length})</button>
      </div>
      <input type="text" id="fn-search" class="search-input" style="width: 250px;" placeholder="Search functions..." oninput="filterFunctionCards()">
    </div>

    <div class="func-list" id="func-list-container">
  `;

  filteredFuncs.forEach(fn => {
    let badge = `<span class="stat-badge badge-clean">Clean</span>`;
    if (fn.status === 'DIVERGED') badge = `<span class="stat-badge badge-diverged">⚡ Diverged (${fn.counts.diverged})</span>`;
    else if (fn.status === 'UNGROUNDED') badge = `<span class="stat-badge badge-ungrounded">⚠️ Ungrounded (${fn.counts.ungrounded})</span>`;
    else if (fn.status === 'OVERCAUTIOUS') badge = `<span class="stat-badge badge-overcautious">🛡️ Overcautious (${fn.counts.overcautious})</span>`;
    else if (fn.status === 'CONCERN') badge = `<span class="stat-badge badge-overcautious">Concern (${fn.counts.concern})</span>`;

    const locsStr = fn.locs.length ? `<span>📍 ${fn.locs.slice(0, 2).join(', ')}</span>` : '';

    html += `
      <div class="func-card" data-title="${fn.title.toLowerCase()}" onclick="navToFunction('${d.object}', '${fn.id}')">
        <div class="func-card-left">
          <div class="func-card-title">
            <span>${escapeHtml(fn.title)}</span>
          </div>
          <div class="func-card-subtitle">
            ${locsStr}
          </div>
        </div>
        <div>
          ${badge}
        </div>
      </div>
    `;
  });

  html += `</div>`;
  document.getElementById('view-object').innerHTML = html;
}

function setObjFilter(status) {
  statusFilter = status;
  renderObjectView();
}

function filterFunctionCards() {
  const val = (document.getElementById('fn-search')?.value || '').toLowerCase();
  const cards = document.querySelectorAll('#func-list-container .func-card');
  cards.forEach(c => {
    const title = c.getAttribute('data-title');
    c.style.display = title.includes(val) ? '' : 'none';
  });
}

function renderFunctionView() {
  if (!currentObject || !currentFunction) return;
  const d = currentObject;
  const fn = currentFunction;

  const availableFiles = Object.keys(d.sources);
  
  // Choose initial file based on function primary_file if available
  let targetFile = availableFiles[0] || '';
  if (fn.primary_file) {
    const matched = availableFiles.find(f => f.includes(fn.primary_file) || fn.primary_file.includes(f.replace('src/mgr/', '')));
    if (matched) targetFile = matched;
  }
  
  codeActiveFile = targetFile;

  let badge = `<span class="stat-badge badge-clean">Clean / Conforming</span>`;
  if (fn.status === 'DIVERGED') badge = `<span class="stat-badge badge-diverged">⚡ Divergence Detected (${fn.counts.diverged})</span>`;
  else if (fn.status === 'UNGROUNDED') badge = `<span class="stat-badge badge-ungrounded">⚠️ Ungrounded Finding (${fn.counts.ungrounded})</span>`;
  else if (fn.status === 'OVERCAUTIOUS') badge = `<span class="stat-badge badge-overcautious">🛡️ Overcautious Guard (${fn.counts.overcautious})</span>`;

  let html = `
    <div class="page-title-row">
      <div>
        <h1 class="page-title">
          <span style="font-family: ui-monospace, SFMono-Regular, Menlo, monospace;">${escapeHtml(fn.title)}</span>
        </h1>
        <div style="margin-top: 6px; display: flex; gap: 12px; align-items: center;">
          <span style="color: var(--text-muted); font-size: 13px;">Object:</span>
          <a class="table-link" onclick="navToObject('${d.object}')">${d.object}</a>
          ${badge}
        </div>
      </div>
      <div style="display: flex; gap: 8px;">
        <button class="filter-btn" onclick="navToObject('${d.object}')">← Back to ${d.object}</button>
      </div>
    </div>

    <!-- Draggable Resizable Split Container -->
    <div class="fn-split-container" id="fn-split-container">
      <!-- Left: Markdown Assessment Details -->
      <div class="fn-pane fn-pane-left" id="fn-pane-left" style="width: ${splitRatioLeft}%;">
        <div class="panel-box">
          <div class="panel-box-header">
            <span>Intent, Contracts & Critique</span>
            <span style="font-size: 11px; color: var(--text-muted);">Reconstructed from git history</span>
          </div>
          <div class="prose" style="max-height: 800px; overflow-y: auto;">
            ${fn.html || '<p>No details available.</p>'}
          </div>
        </div>
      </div>

      <!-- Draggable Splitter Handle -->
      <div class="fn-splitter" id="fn-splitter" title="Drag to resize panes"></div>

      <!-- Right: Implementation Code Browser -->
      <div class="fn-pane fn-pane-right" id="fn-pane-right">
        <div class="panel-box">
          <div class="panel-box-header">
            <span>Source Code</span>
            <div>
              ${renderFileSelector(availableFiles)}
            </div>
          </div>
          <div class="code-legend">
            <span class="legend-item"><span class="legend-box" style="background: rgba(88, 166, 255, 0.2); border-color: var(--color-accent);"></span> Function Scope</span>
            <span class="legend-item"><span class="legend-box" style="background: rgba(218, 54, 51, 0.3); border-color: var(--color-diverged-border);"></span> Divergence</span>
            <span class="legend-item"><span class="legend-box" style="background: rgba(210, 153, 34, 0.3); border-color: var(--color-ungrounded-border);"></span> Ungrounded</span>
            <span class="legend-item"><span class="legend-box" style="background: rgba(163, 113, 247, 0.3); border-color: var(--color-overcautious-border);"></span> Overcautious</span>
          </div>
          <div class="code-container" id="code-container-view">
            ${renderSourceCodeLines(d.sources[codeActiveFile] || '', codeActiveFile, fn)}
          </div>
        </div>
      </div>
    </div>
  `;

  document.getElementById('view-function').innerHTML = html;

  // Initialize mouse drag events on splitter
  initSplitter();

  // Scroll to relevant line
  scrollToRelevantLine(codeActiveFile, fn);
}

function initSplitter() {
  const splitter = document.getElementById('fn-splitter');
  const container = document.getElementById('fn-split-container');
  const leftPane = document.getElementById('fn-pane-left');

  if (!splitter || !container || !leftPane) return;

  let isDragging = false;

  splitter.addEventListener('mousedown', (e) => {
    isDragging = true;
    splitter.classList.add('dragging');
    document.body.style.cursor = 'col-resize';
    document.body.style.userSelect = 'none';
    e.preventDefault();
  });

  document.addEventListener('mousemove', (e) => {
    if (!isDragging) return;
    const containerRect = container.getBoundingClientRect();
    const offsetX = e.clientX - containerRect.left;
    let percentage = (offsetX / containerRect.width) * 100;

    // Constrain range between 20% and 80%
    if (percentage < 20) percentage = 20;
    if (percentage > 80) percentage = 80;

    splitRatioLeft = percentage;
    leftPane.style.width = `${percentage}%`;
  });

  document.addEventListener('mouseup', () => {
    if (isDragging) {
      isDragging = false;
      splitter.classList.remove('dragging');
      document.body.style.cursor = '';
      document.body.style.userSelect = '';
      localStorage.setItem('ceph_mgr_split_ratio', splitRatioLeft.toFixed(2));
    }
  });
}

function scrollToRelevantLine(activeFile, fn) {
  setTimeout(() => {
    // Priority: concern line first, then primary line
    let scrollLine = 0;
    const concernRanges = getConcernRangesForFile(activeFile, fn);
    if (concernRanges.length > 0) {
      scrollLine = concernRanges[0][0];
    } else if (fn.primary_line > 0 && isMatchingFile(activeFile, fn.primary_file)) {
      scrollLine = fn.primary_line;
    }

    if (scrollLine > 0) {
      const el = document.getElementById(`line-row-${scrollLine}`);
      if (el) {
        el.scrollIntoView({ block: 'center', behavior: 'smooth' });
      }
    }
  }, 100);
}

function isMatchingFile(activeFile, targetFile) {
  if (!targetFile) return true;
  const a = activeFile.replace('src/mgr/', '');
  const t = targetFile.replace('src/mgr/', '');
  return a.includes(t) || t.includes(a);
}

function getConcernRangesForFile(activeFile, fn) {
  if (!fn.concern_lines) return [];
  const activeBase = activeFile.replace('src/mgr/', '');
  const ext = activeBase.split('.').pop(); // cc or h
  
  let ranges = [];
  for (let [k, rList] of Object.entries(fn.concern_lines)) {
    const kClean = k.replace('src/mgr/', '');
    if (kClean === activeBase || kClean === `.${ext}` || kClean === ext || (k === 'default' && fn.status !== 'CLEAN')) {
      ranges.push(...rList);
    }
  }
  return ranges;
}

function renderFileSelector(files) {
  if (!files || files.length === 0) return `<span style="font-size: 12px; color: var(--text-muted);">No source loaded</span>`;
  let select = `<select class="code-file-select" onchange="changeCodeFile(this.value)">`;
  files.forEach(f => {
    select += `<option value="${f}" ${f === codeActiveFile ? 'selected' : ''}>${f}</option>`;
  });
  select += `</select>`;
  return select;
}

function changeCodeFile(newFile) {
  codeActiveFile = newFile;
  const container = document.getElementById('code-container-view');
  if (container && currentObject && currentObject.sources[codeActiveFile]) {
    container.innerHTML = renderSourceCodeLines(currentObject.sources[codeActiveFile], codeActiveFile, currentFunction);
    scrollToRelevantLine(codeActiveFile, currentFunction);
  }
}

function renderSourceCodeLines(sourceText, activeFile, fn) {
  if (!sourceText) return `<div style="padding: 20px; color: var(--text-muted); text-align: center;">Source file content not available.</div>`;
  const lines = sourceText.split('\n');
  
  const concernRanges = getConcernRangesForFile(activeFile, fn);
  const isPrimaryFile = isMatchingFile(activeFile, fn.primary_file);
  const funcStartLine = isPrimaryFile ? fn.primary_line : 0;

  let html = `<div class="code-table">`;
  lines.forEach((line, idx) => {
    const lineNum = idx + 1;
    
    // Check if line falls into a concern range
    let concernType = null;
    for (let r of concernRanges) {
      if (lineNum >= r[0] && lineNum <= r[1]) {
        concernType = fn.status;
        break;
      }
    }

    let highlightClass = '';
    if (concernType) {
      if (concernType === 'DIVERGED') highlightClass = 'highlight-concern-diverged';
      else if (concernType === 'UNGROUNDED') highlightClass = 'highlight-concern-ungrounded';
      else if (concernType === 'OVERCAUTIOUS') highlightClass = 'highlight-concern-overcautious';
      else highlightClass = 'highlight-concern-general';
    } else if (funcStartLine > 0 && lineNum >= funcStartLine && lineNum <= funcStartLine + 3) {
      highlightClass = 'highlight-func';
    }

    html += `
      <div class="code-line ${highlightClass}" id="line-row-${lineNum}">
        <div class="line-num">${lineNum}</div>
        <div class="line-text">${escapeHtml(line) || ' '}</div>
      </div>
    `;
  });
  html += `</div>`;
  return html;
}

function escapeHtml(str) {
  if (!str) return '';
  return str.replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#039;');
}
</script>

</body>
</html>
"""

def generate_html():
    dataset_path = os.path.join(SCRIPT_DIR, "dataset.json")
    if not os.path.exists(dataset_path):
        dataset_path = os.path.join(REPO_ROOT, "dataset.json")
    with open(dataset_path, "r", encoding="utf-8") as fh:
        dataset = json.load(fh)

    json_str = json.dumps(dataset)
    html_output = HTML_TEMPLATE.replace("%%DATA_JSON%%", json_str)

    output_path = os.path.join(REPO_ROOT, "Outputs", "ceph-mgr-intents-assessment.html")
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as out:
        out.write(html_output)
    
    print(f"Generated standalone HTML artifact at {output_path}")
    print(f"File size: {os.path.getsize(output_path) / 1024:.2f} KB ({os.path.getsize(output_path) / 1024 / 1024:.2f} MB)")

if __name__ == "__main__":
    generate_html()
