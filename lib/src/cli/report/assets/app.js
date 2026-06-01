/* =====================================================================
   alea quality-gate report — app.js
   Vanilla JS. No build, no network. Reads window.__ALEA_REPORT__.
   ===================================================================== */
(function () {
  "use strict";

  var REPORT = window.__ALEA_REPORT__ || { results: [], passed: true, project: "", gate: "", timestamp: "" };

  /* ---------- severity model ---------- */
  var SEV_ORDER = { blocker: 0, critical: 1, major: 2, minor: 3 };
  var SEV_LIST = ["blocker", "critical", "major", "minor"];
  var SEV_LABEL = { blocker: "Blocker", critical: "Critical", major: "Major", minor: "Minor" };
  var BLOCKING = { blocker: true, critical: true };

  // shape-distinct icons (never color alone)
  var ICON = {
    blocker: '<svg viewBox="0 0 16 16" width="14" height="14" aria-hidden="true"><path d="M5.4 1.3h5.2L14.7 5.4v5.2L10.6 14.7H5.4L1.3 10.6V5.4z" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round"/><line x1="8" y1="4.4" x2="8" y2="9" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/><circle cx="8" cy="11.4" r="0.95" fill="currentColor"/></svg>',
    critical: '<svg viewBox="0 0 16 16" width="14" height="14" aria-hidden="true"><path d="M8 1.7 15 14H1z" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round"/><line x1="8" y1="6" x2="8" y2="10" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/><circle cx="8" cy="12" r="0.95" fill="currentColor"/></svg>',
    major: '<svg viewBox="0 0 16 16" width="14" height="14" aria-hidden="true"><path d="M8 1.6 14.4 8 8 14.4 1.6 8z" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round"/><line x1="8" y1="5.4" x2="8" y2="8.9" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/><circle cx="8" cy="10.9" r="0.9" fill="currentColor"/></svg>',
    minor: '<svg viewBox="0 0 16 16" width="14" height="14" aria-hidden="true"><circle cx="8" cy="8" r="5.7" fill="none" stroke="currentColor" stroke-width="1.5"/><line x1="5.4" y1="8" x2="10.6" y2="8" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/></svg>'
  };
  var TWIRL = '<svg class="twirl" viewBox="0 0 16 16" width="14" height="14" aria-hidden="true"><path d="M6 4l5 4-5 4" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></svg>';
  var ICON_DIR = '<svg viewBox="0 0 16 16" width="15" height="15" aria-hidden="true"><path d="M1.5 4.2c0-.7.5-1.2 1.2-1.2h3l1.4 1.6h6.2c.7 0 1.2.5 1.2 1.2v6.4c0 .7-.5 1.2-1.2 1.2H2.7c-.7 0-1.2-.5-1.2-1.2z" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linejoin="round"/></svg>';
  var ICON_FILE = '<svg viewBox="0 0 16 16" width="14" height="14" aria-hidden="true"><path d="M4 1.5h5l3 3v9.2c0 .4-.3.8-.8.8H4.3a.8.8 0 0 1-.8-.8V2.3c0-.4.3-.8.8-.8z" fill="none" stroke="currentColor" stroke-width="1.3" stroke-linejoin="round"/><path d="M9 1.6v3.1h3" fill="none" stroke="currentColor" stroke-width="1.3" stroke-linejoin="round"/></svg>';
  var ICON_CHECK = '<svg viewBox="0 0 16 16" width="16" height="16" aria-hidden="true"><circle cx="8" cy="8" r="6.6" fill="none" stroke="currentColor" stroke-width="1.5"/><path d="M5.2 8.2l2 2 3.6-4" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></svg>';

  var ANALYZER_LABEL = {
    build_method_complexity: "Build method complexity",
    code_complexity: "Code complexity",
    design_principles: "Design principles",
    dry_detection: "DRY / duplication",
    flutter_antipatterns: "Flutter anti-patterns",
    layer_integrity: "Layer integrity",
    meaningful_test: "Meaningful tests",
    package_boundary: "Package boundaries",
    performance: "Performance",
    project_conventions: "Project conventions",
    security: "Security",
    state_mgmt: "State management",
    testing: "Testing",
    visual_fidelity: "Visual fidelity",
    widget_inventory: "Widget inventory",
    widget_purity: "Widget purity",
    wiring_cohesion: "Wiring cohesion"
  };
  // friendly nouns for the verdict subtitle
  var ANALYZER_NOUN = {
    security: "architecture", layer_integrity: "architecture", package_boundary: "architecture",
    code_complexity: "complexity", build_method_complexity: "complexity",
    design_principles: "design", visual_fidelity: "visual fidelity",
    state_mgmt: "state", testing: "test", performance: "performance"
  };
  function analyzerLabel(a) { return ANALYZER_LABEL[a] || a.replace(/_/g, " ").replace(/\b\w/g, function (c) { return c.toUpperCase(); }); }

  /* ---------- flatten ---------- */
  var FINDINGS = [];
  (REPORT.results || []).forEach(function (res) {
    (res.issues || []).forEach(function (i) {
      var sev = i.severity || "minor";
      var ruleId = i.ruleId || i.rule_id || (res.analyzer + "/" + (i.rule || ""));
      var fix = (i.suggestedFix !== undefined) ? i.suggestedFix : (i.suggested_fix !== undefined ? i.suggested_fix : null);
      var file = i.file || "";
      FINDINGS.push({
        file: file, line: i.line || 0, rule: i.rule || "", ruleId: ruleId,
        message: i.message || "", suggestedFix: fix, severity: sev,
        analyzer: res.analyzer, blocking: !!BLOCKING[sev],
        _s: (file + " " + ruleId + " " + (i.message || "")).toLowerCase()
      });
    });
  });
  var TOTAL = FINDINGS.length;
  var TOTAL_BY_SEV = countBySev(FINDINGS);

  function countBySev(arr) {
    var c = { blocker: 0, critical: 0, major: 0, minor: 0 };
    for (var i = 0; i < arr.length; i++) c[arr[i].severity]++;
    return c;
  }
  function worstSevIndex(arr) {
    var w = 99; for (var i = 0; i < arr.length; i++) { var s = SEV_ORDER[arr[i].severity]; if (s < w) w = s; } return w;
  }

  /* ---------- state ---------- */
  var S = {
    grouping: "severity",
    filters: { blocker: true, critical: true, major: false, minor: false },
    search: "",
    open: { severity: {}, analyzer: {} },   // explicit user toggles (group key -> bool)
    treeOpen: {},                           // path -> bool (explicit override)
    page: {}                                // group key -> count shown
  };

  /* ---------- filtering ---------- */
  function filtered() {
    var q = S.search.trim().toLowerCase();
    var out = [];
    for (var i = 0; i < FINDINGS.length; i++) {
      var f = FINDINGS[i];
      if (!S.filters[f.severity]) continue;
      if (q && f._s.indexOf(q) === -1) continue;
      out.push(f);
    }
    return out;
  }
  function sortFindings(arr) {
    return arr.slice().sort(function (a, b) {
      var d = SEV_ORDER[a.severity] - SEV_ORDER[b.severity]; if (d) return d;
      if (a.file !== b.file) return a.file < b.file ? -1 : 1;
      return a.line - b.line;
    });
  }

  /* =====================================================================
     RENDER HELPERS
     ===================================================================== */
  function el(tag, cls, html) { var e = document.createElement(tag); if (cls) e.className = cls; if (html != null) e.innerHTML = html; return e; }
  function esc(s) { return String(s).replace(/[&<>"]/g, function (c) { return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]; }); }

  // shared FINDING ROW — identical across all three grouping axes
  function findingRow(f) {
    var row = el("div", "finding sev-" + f.severity);
    row.setAttribute("data-sev", f.severity);

    // severity chip
    var chip = el("span", "sev-chip", '<span class="sc-ico">' + ICON[f.severity] + "</span>" + SEV_LABEL[f.severity]);
    row.appendChild(chip);

    // path (middle-truncated: dir tail ellipsised, filename:line kept)
    var slash = f.file.lastIndexOf("/");
    var dir = slash >= 0 ? f.file.slice(0, slash + 1) : "";
    var name = slash >= 0 ? f.file.slice(slash + 1) : f.file;
    var pathBtn = el("span", "path");
    pathBtn.title = f.file + ":" + f.line;
    pathBtn.innerHTML = '<span class="p-dir">' + esc(dir) + '</span><span class="p-file">' + esc(name) + '</span><span class="p-line">:' + f.line + "</span>";
    row.appendChild(pathBtn);

    // copy file:line
    var copy = el("button", "copy");
    copy.type = "button";
    copy.setAttribute("aria-label", "Copy " + name + ":" + f.line + " path");
    copy.innerHTML = '<svg viewBox="0 0 16 16" width="14" height="14" aria-hidden="true"><rect x="5.3" y="5.3" width="8.2" height="8.2" rx="1.6" fill="none" stroke="currentColor" stroke-width="1.4"/><path d="M10.7 5.3V3.6c0-.9-.7-1.6-1.6-1.6H3.6C2.7 2 2 2.7 2 3.6V9c0 .9.7 1.6 1.6 1.6h1.7" fill="none" stroke="currentColor" stroke-width="1.4"/></svg>';
    copy.addEventListener("click", function (e) { e.stopPropagation(); copyPath(f.file + ":" + f.line, copy); });
    row.appendChild(copy);

    // ruleId
    row.appendChild(el("span", "rule-id", esc(f.ruleId)));

    // message
    row.appendChild(el("span", "msg", esc(f.message)));

    // fix (only if present)
    if (f.suggestedFix) {
      var ft = el("button", "fix-toggle", '<span class="fx-tw">' + TWIRL.replace('class="twirl"', '') + "</span>Fix");
      ft.type = "button"; ft.setAttribute("aria-expanded", "false");
      var panel = el("div", "fix-panel", "<b>Suggested fix —</b> " + esc(f.suggestedFix));
      panel.hidden = true;
      ft.addEventListener("click", function (e) {
        e.stopPropagation();
        var open = ft.getAttribute("aria-expanded") === "true";
        ft.setAttribute("aria-expanded", String(!open));
        panel.hidden = open;
      });
      row.appendChild(ft);
      row.appendChild(panel);
    }
    return row;
  }

  function miniChips(counts) {
    var wrap = el("span", "minichips");
    for (var k = 0; k < SEV_LIST.length; k++) {
      var s = SEV_LIST[k];
      if (!counts[s]) continue;
      var c = el("span", "minichip sev-" + s);
      c.innerHTML = '<span class="mc-ico">' + ICON[s] + "</span>" + counts[s];
      c.title = counts[s] + " " + SEV_LABEL[s].toLowerCase();
      wrap.appendChild(c);
    }
    return wrap;
  }

  /* =====================================================================
     COPY + TOAST
     ===================================================================== */
  var toastEl = document.getElementById("toast");
  var toastTimer = null;
  function showToast(msg) {
    toastEl.innerHTML = '<span class="t-ico">' + ICON_CHECK + "</span>" + esc(msg);
    toastEl.hidden = false;
    requestAnimationFrame(function () { toastEl.classList.add("show"); });
    clearTimeout(toastTimer);
    toastTimer = setTimeout(function () {
      toastEl.classList.remove("show");
      setTimeout(function () { toastEl.hidden = true; }, 200);
    }, 1900);
  }
  function copyPath(text, btn) {
    function ok() {
      btn.classList.add("copied");
      setTimeout(function () { btn.classList.remove("copied"); }, 1200);
      showToast("Copied " + text);
    }
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(ok, function () { legacyCopy(text, ok); });
    } else { legacyCopy(text, ok); }
  }
  function legacyCopy(text, ok) {
    var ta = document.createElement("textarea");
    ta.value = text; ta.style.position = "fixed"; ta.style.opacity = "0";
    document.body.appendChild(ta); ta.select();
    try { document.execCommand("copy"); ok(); } catch (e) { showToast("Copy failed"); }
    document.body.removeChild(ta);
  }

  /* =====================================================================
     PAGINATION (severity + analyzer groups)
     ===================================================================== */
  var PAGE = 50;
  function renderPaged(container, items, key) {
    var shown = S.page[key] || PAGE;
    if (shown > items.length) shown = items.length;
    var frag = document.createDocumentFragment();
    for (var i = 0; i < shown; i++) frag.appendChild(findingRow(items[i]));
    container.appendChild(frag);
    if (items.length > shown) {
      var remaining = items.length - shown;
      var more = el("button", "show-more");
      more.type = "button";
      more.textContent = "Show " + Math.min(PAGE, remaining) + " more — " + remaining + " hidden";
      more.addEventListener("click", function () {
        S.page[key] = shown + PAGE;
        var parent = container;
        // re-render just this group's body
        container.innerHTML = "";
        renderPaged(container, items, key);
      });
      container.appendChild(more);
    }
  }

  /* =====================================================================
     GROUP SECTION (collapsible) — used by severity + analyzer
     ===================================================================== */
  function groupSection(opts) {
    // opts: {key, name, accent, desc, statusPill, counts, items, open}
    var sec = el("div", "group");
    sec.setAttribute("data-open", String(opts.open));

    var head = el("button", "group-head");
    head.type = "button";
    head.setAttribute("aria-expanded", String(opts.open));

    head.innerHTML = TWIRL;
    var title = el("div", "group-title");
    var name = el("div", "group-name");
    if (opts.accent) name.innerHTML = '<span class="accent-bar" style="background:' + opts.accent + '"></span>';
    name.appendChild(document.createTextNode(opts.name));
    title.appendChild(name);
    if (opts.desc) title.appendChild(el("div", "group-desc", esc(opts.desc)));
    head.appendChild(title);

    var meta = el("div", "group-meta");
    if (opts.statusPill) {
      var pill = el("span", "status-pill " + opts.statusPill.cls, opts.statusPill.text);
      meta.appendChild(pill);
    }
    meta.appendChild(miniChips(opts.counts));
    head.appendChild(meta);
    sec.appendChild(head);

    var body = el("div", "group-body");
    sec.appendChild(body);

    var built = false;
    function build() {
      if (built) return; built = true;
      renderPaged(body, opts.items, opts.key);
    }
    if (opts.open) build();

    head.addEventListener("click", function () {
      var open = sec.getAttribute("data-open") === "true";
      open = !open;
      sec.setAttribute("data-open", String(open));
      head.setAttribute("aria-expanded", String(open));
      S.open[opts.scope][opts.key] = open;
      if (open) build();
    });
    return sec;
  }

  /* =====================================================================
     AXIS 1 — SEVERITY  (Blocking / Advisory)
     ===================================================================== */
  function renderSeverity(root, items) {
    var blocking = sortFindings(items.filter(function (f) { return f.blocking; }));
    var advisory = sortFindings(items.filter(function (f) { return !f.blocking; }));

    if (blocking.length === 0) {
      // green empty-state + auto-expand advisory
      root.appendChild(emptyState(true,
        "Nothing blocks this gate",
        "No blocker or critical findings in the current filter. The items below are advisory — they don't fail the gate."));
    }

    // BLOCKING
    var blkOpen = userOpen("severity", "blocking", blocking.length > 0);
    root.appendChild(groupSection({
      scope: "severity", key: "blocking", name: "Blocking", open: blkOpen,
      accent: "var(--blk-fg)",
      desc: blocking.length ? "Blocker + critical findings — these fail the gate" : "No blocking findings in the current filter",
      counts: countBySev(blocking), items: blocking
    }));

    // ADVISORY
    var advDefault = blocking.length === 0;
    var advOpen = userOpen("severity", "advisory", advDefault);
    root.appendChild(groupSection({
      scope: "severity", key: "advisory", name: "Advisory", open: advOpen,
      accent: "var(--maj-fg)",
      desc: advisory.length ? "Major + minor findings — informational, do not fail the gate" : "No advisory findings in the current filter",
      counts: countBySev(advisory), items: advisory
    }));
  }
  function userOpen(scope, key, def) {
    var o = S.open[scope];
    return Object.prototype.hasOwnProperty.call(o, key) ? o[key] : def;
  }

  /* =====================================================================
     AXIS 2 — ANALYZER (flat groups)
     ===================================================================== */
  function renderAnalyzer(root, items) {
    var byA = {};
    items.forEach(function (f) { (byA[f.analyzer] = byA[f.analyzer] || []).push(f); });
    var analyzers = Object.keys(byA).map(function (a) {
      var arr = byA[a];
      return { a: a, arr: arr, counts: countBySev(arr), worst: worstSevIndex(arr), blocking: arr.some(function (f) { return f.blocking; }) };
    });
    analyzers.sort(function (x, y) {
      if (x.blocking !== y.blocking) return x.blocking ? -1 : 1;
      if (x.worst !== y.worst) return x.worst - y.worst;
      if (x.arr.length !== y.arr.length) return y.arr.length - x.arr.length;
      return x.a < y.a ? -1 : 1;
    });

    analyzers.forEach(function (g) {
      var open = userOpen("analyzer", g.a, g.blocking);
      root.appendChild(groupSection({
        scope: "analyzer", key: g.a, name: analyzerLabel(g.a), open: open,
        accent: g.blocking ? "var(--blk-fg)" : "var(--" + (["blk", "crit", "maj", "min"][g.worst]) + "-fg)",
        desc: g.a + " · " + g.arr.length + (g.arr.length === 1 ? " finding" : " findings"),
        statusPill: g.blocking ? { cls: "fail", text: "Fails gate" } : { cls: "pass", text: "Advisory" },
        counts: g.counts, items: sortFindings(g.arr)
      }));
    });
  }

  /* =====================================================================
     AXIS 3 — FILE TREE
     ===================================================================== */
  function buildTree(items) {
    var root = { seg: "", kind: "dir", children: {}, order: [] };
    items.forEach(function (f) {
      var parts = f.file.split("/");
      var cur = root;
      for (var k = 0; k < parts.length; k++) {
        var seg = parts[k], isFile = k === parts.length - 1;
        if (!cur.children[seg]) {
          cur.children[seg] = { seg: seg, kind: isFile ? "file" : "dir", children: {}, order: [], findings: [] };
          cur.order.push(seg);
        }
        cur = cur.children[seg];
      }
      cur.findings.push(f);
    });
    return root;
  }
  // produce compressed display nodes with aggregates + paths
  function toDisplay(node, parentPath) {
    if (node.kind === "file") {
      var path = parentPath + "/" + node.seg;
      return {
        kind: "file", label: node.seg, path: path,
        findings: sortFindings(node.findings),
        counts: countBySev(node.findings), worst: worstSevIndex(node.findings), total: node.findings.length
      };
    }
    // dir: compress single dir-child chains
    var labelParts = [node.seg], cur = node;
    while (cur.order.length === 1) {
      var only = cur.children[cur.order[0]];
      if (only.kind !== "dir") break;
      labelParts.push(only.seg); cur = only;
    }
    var label = labelParts.join("/");
    var path = (parentPath ? parentPath + "/" : "") + label;
    var children = cur.order.map(function (seg) { return toDisplay(cur.children[seg], path); });
    // aggregates
    var counts = { blocker: 0, critical: 0, major: 0, minor: 0 }, total = 0, worst = 99;
    children.forEach(function (c) {
      SEV_LIST.forEach(function (s) { counts[s] += c.counts[s]; });
      total += c.total; if (c.worst < worst) worst = c.worst;
    });
    // sort siblings: worst severity, then count desc, then alpha
    children.sort(function (a, b) {
      if (a.worst !== b.worst) return a.worst - b.worst;
      if (a.total !== b.total) return b.total - a.total;
      return a.label < b.label ? -1 : 1;
    });
    return { kind: "dir", label: label, path: path, children: children, counts: counts, total: total, worst: worst };
  }

  function dirHasBlocking(n) { return n.counts.blocker + n.counts.critical > 0; }

  function renderFile(root, items) {
    var anyBlocking = items.some(function (f) { return f.blocking; });
    if (!anyBlocking) {
      root.appendChild(emptyState(true,
        "Nothing blocks this gate",
        "No blocking findings match the current filter. Expand folders below to browse advisory findings by location."));
    }
    var tree = buildTree(items);
    var topNodes = tree.order.map(function (seg) { return toDisplay(tree.children[seg], ""); });
    topNodes.sort(function (a, b) {
      if (a.worst !== b.worst) return a.worst - b.worst;
      if (a.total !== b.total) return b.total - a.total;
      return a.label < b.label ? -1 : 1;
    });

    var wrap = el("div", "tree-wrap");
    var treeEl = el("div", "tree");
    treeEl.setAttribute("role", "tree");
    treeEl.setAttribute("aria-label", "Findings by file");
    topNodes.forEach(function (n) { treeEl.appendChild(treeNode(n, 1, anyBlocking)); });
    wrap.appendChild(treeEl);
    root.appendChild(wrap);
    initTreeKeyboard(treeEl);
  }

  function treeNode(node, level, autoExpandAllowed) {
    var wrap = document.createElement("div");
    var item = el("div", "treeitem " + (node.kind === "dir" ? "ti-dir" : "ti-file") + " sev-" + sevName(node.worst));
    item.setAttribute("role", "treeitem");
    item.setAttribute("aria-level", String(level));
    item.tabIndex = -1;

    var defOpen = node.kind === "dir"
      ? (autoExpandAllowed && dirHasBlocking(node))
      : (autoExpandAllowed && dirHasBlocking(node)); // files: expand if they hold blocking
    var open = Object.prototype.hasOwnProperty.call(S.treeOpen, node.path) ? S.treeOpen[node.path] : defOpen;

    // twirl or spacer
    item.innerHTML = TWIRL;
    item.setAttribute("aria-expanded", String(open));

    var ico = el("span", "ti-ico", node.kind === "dir" ? ICON_DIR : ICON_FILE);
    item.appendChild(ico);

    var label = el("span", "ti-label");
    if (node.kind === "file") {
      label.innerHTML = esc(node.label) + (node.findings.length === 1 ? '<span class="tf-line">:' + node.findings[0].line + "</span>" : "");
    } else {
      label.textContent = node.label;
    }
    label.title = node.path.replace(/^\//, "");
    item.appendChild(label);

    var meta = el("div", "ti-meta");
    meta.appendChild(miniChips(node.counts));
    // compact worst+total for narrow screens
    var wc = el("span", "ti-worst-chip sev-" + sevName(node.worst));
    wc.innerHTML = '<span class="mc-ico">' + ICON[sevName(node.worst)] + "</span>" + node.total;
    meta.appendChild(wc);
    item.appendChild(meta);

    item.setAttribute("aria-label",
      (node.kind === "dir" ? "Folder " : "File ") + node.path.replace(/^\//, "") + ", " + node.total + (node.total === 1 ? " finding" : " findings"));

    wrap.appendChild(item);

    // children group (lazy)
    var group = el("div", "tree-group");
    group.setAttribute("role", "group");
    group.hidden = !open;
    wrap.appendChild(group);

    var built = false;
    function build() {
      if (built) return; built = true;
      if (node.kind === "dir") {
        node.children.forEach(function (c) { group.appendChild(treeNode(c, level + 1, autoExpandAllowed)); });
      } else {
        var ff = el("div", "file-findings");
        node.findings.forEach(function (f) { ff.appendChild(findingRow(f)); });
        group.appendChild(ff);
      }
    }
    if (open) build();

    function toggle() {
      var isOpen = item.getAttribute("aria-expanded") === "true";
      isOpen = !isOpen;
      item.setAttribute("aria-expanded", String(isOpen));
      group.hidden = !isOpen;
      S.treeOpen[node.path] = isOpen;
      if (isOpen) build();
    }
    item.addEventListener("click", function () { toggle(); focusItem(item); });
    item._toggle = toggle;
    item._isOpen = function () { return item.getAttribute("aria-expanded") === "true"; };
    return wrap;
  }
  function sevName(idx) { return SEV_LIST[idx] || "minor"; }

  /* ---------- tree keyboard navigation ---------- */
  var focusedItem = null;
  function focusItem(item) {
    if (focusedItem) { focusedItem.classList.remove("focused"); focusedItem.tabIndex = -1; }
    focusedItem = item;
    item.tabIndex = 0; item.classList.add("focused"); item.focus();
  }
  function visibleItems(treeEl) {
    return Array.prototype.filter.call(treeEl.querySelectorAll(".treeitem"), function (it) {
      // visible if no ancestor group is hidden
      var p = it.parentElement;
      while (p && p !== treeEl) {
        if (p.classList.contains("tree-group") && p.hidden) return false;
        p = p.parentElement;
      }
      return true;
    });
  }
  function initTreeKeyboard(treeEl) {
    var first = treeEl.querySelector(".treeitem");
    if (first) first.tabIndex = 0;
    treeEl.addEventListener("keydown", function (e) {
      var items = visibleItems(treeEl);
      var cur = document.activeElement.closest ? document.activeElement.closest(".treeitem") : null;
      if (!cur || items.indexOf(cur) === -1) cur = items[0];
      var idx = items.indexOf(cur);
      switch (e.key) {
        case "ArrowDown": e.preventDefault(); if (idx < items.length - 1) focusItem(items[idx + 1]); break;
        case "ArrowUp": e.preventDefault(); if (idx > 0) focusItem(items[idx - 1]); break;
        case "ArrowRight":
          e.preventDefault();
          if (cur.getAttribute("aria-expanded") === "false") { cur._toggle(); }
          else { var next = items[idx + 1]; if (next && +next.getAttribute("aria-level") > +cur.getAttribute("aria-level")) focusItem(next); }
          break;
        case "ArrowLeft":
          e.preventDefault();
          if (cur.getAttribute("aria-expanded") === "true") { cur._toggle(); }
          else {
            var lvl = +cur.getAttribute("aria-level");
            for (var j = idx - 1; j >= 0; j--) { if (+items[j].getAttribute("aria-level") < lvl) { focusItem(items[j]); break; } }
          }
          break;
        case "Enter": case " ": e.preventDefault(); cur._toggle(); break;
        case "Home": e.preventDefault(); focusItem(items[0]); break;
        case "End": e.preventDefault(); focusItem(items[items.length - 1]); break;
      }
    });
  }

  /* ---------- empty state ---------- */
  function emptyState(green, title, sub) {
    var e = el("div", "empty" + (green ? "" : " neutral"));
    e.innerHTML = '<span class="e-ico">' + ICON_CHECK + '</span><span class="e-text"><span class="e-title">' + esc(title) + '</span><span class="e-sub">' + esc(sub) + "</span></span>";
    return e;
  }

  /* =====================================================================
     TOP-LEVEL RENDER
     ===================================================================== */
  var resultsEl = document.getElementById("results");
  function render() {
    var items = filtered();
    updateCounter(items.length);
    resultsEl.innerHTML = "";

    if (items.length === 0) {
      var msg = TOTAL === 0 ? "This report contains no findings." : "No findings match the current filters and search.";
      resultsEl.appendChild(el("div", "no-results", esc(msg)));
      return;
    }
    if (S.grouping === "severity") renderSeverity(resultsEl, items);
    else if (S.grouping === "analyzer") renderAnalyzer(resultsEl, items);
    else renderFile(resultsEl, items);
  }

  function resetPaging() { S.page = {}; }

  /* =====================================================================
     HEADER WIRING
     ===================================================================== */
  function buildHeader() {
    // run meta
    var meta = document.getElementById("runMeta");
    var ts = REPORT.timestamp ? new Date(REPORT.timestamp) : null;
    var tstr = ts && !isNaN(ts) ? ts.toLocaleString(undefined, { year: "numeric", month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" }) : (REPORT.timestamp || "");
    meta.innerHTML =
      "Project <code>" + esc(REPORT.project || "—") + "</code>" +
      '<span class="msep">·</span>gate <code>' + esc(REPORT.gate || "—") + "</code>" +
      '<span class="msep">·</span>' + esc(tstr);

    // verdict
    var verdict = document.getElementById("verdict");
    var passed = REPORT.passed;
    verdict.className = "verdict " + (passed ? "pass" : "fail");
    var sub = verdictSubtitle(passed);
    verdict.innerHTML =
      '<span class="verdict-badge">' + (passed ? ICON_CHECK : ICON.blocker) + (passed ? "PASS" : "FAIL") + "</span>" +
      '<span class="verdict-text"><span class="verdict-title">' + (passed ? "Quality gate passed" : "Quality gate failed") + '</span><span class="verdict-sub">' + sub + "</span></span>";

    // tallies
    var tallies = document.getElementById("tallies");
    tallies.innerHTML = "";
    SEV_LIST.forEach(function (s) {
      var t = el("div", "tally sev-" + s);
      t.innerHTML = '<span class="ti">' + ICON[s] + '</span><span class="tcol"><span class="tnum">' + TOTAL_BY_SEV[s] + '</span><span class="tlab">' + SEV_LABEL[s] + "</span></span>";
      tallies.appendChild(t);
    });
    tallies.appendChild(el("span", "tally-sep"));
    var tot = el("div", "tally tally-total");
    tot.innerHTML = '<span class="tcol"><span class="tnum">' + TOTAL + '</span><span class="tlab">Total findings</span></span>';
    tallies.appendChild(tot);

    // filter chips
    document.querySelectorAll(".fchip").forEach(function (chip) {
      var sev = chip.getAttribute("data-sev");
      var input = chip.querySelector("input");
      var body = chip.querySelector(".fchip-body");
      body.innerHTML = '<span class="fchip-ico">' + ICON[sev] + '</span>' + SEV_LABEL[sev] + ' <span class="fchip-n">' + TOTAL_BY_SEV[sev] + "</span>";
      chip.classList.add("sev-" + sev);
      chip.classList.toggle("on", input.checked);
      input.addEventListener("change", function () {
        S.filters[sev] = input.checked;
        chip.classList.toggle("on", input.checked);
        resetPaging();
        render();
      });
    });

    // segmented control
    document.querySelectorAll(".seg-btn").forEach(function (btn) {
      btn.addEventListener("click", function () { setGrouping(btn.getAttribute("data-group")); });
      btn.addEventListener("keydown", function (e) {
        if (e.key === "ArrowRight" || e.key === "ArrowLeft") {
          e.preventDefault();
          var btns = Array.prototype.slice.call(document.querySelectorAll(".seg-btn"));
          var i = btns.indexOf(btn);
          var n = e.key === "ArrowRight" ? (i + 1) % btns.length : (i - 1 + btns.length) % btns.length;
          btns[n].focus(); setGrouping(btns[n].getAttribute("data-group"));
        }
      });
    });

    // search (debounced ~150ms)
    var search = document.getElementById("search");
    var clear = document.getElementById("searchClear");
    var deb = null;
    search.addEventListener("input", function () {
      clear.hidden = !search.value;
      clearTimeout(deb);
      deb = setTimeout(function () {
        S.search = search.value;
        resetPaging();
        render();
      }, 150);
    });
    clear.addEventListener("click", function () {
      search.value = ""; clear.hidden = true; S.search = ""; resetPaging(); render(); search.focus();
    });
  }

  function verdictSubtitle(passed) {
    if (passed) return "All gating analyzers passed · " + TOTAL + " advisory findings noted.";
    var blockers = FINDINGS.filter(function (f) { return f.blocking; });
    // group by friendly noun
    var byNoun = {};
    blockers.forEach(function (f) {
      var noun = ANALYZER_NOUN[f.analyzer] || f.analyzer.replace(/_/g, " ");
      byNoun[noun] = (byNoun[noun] || 0) + 1;
    });
    var parts = Object.keys(byNoun).map(function (n) {
      return "<b>" + byNoun[n] + "</b> " + esc(n) + (byNoun[n] === 1 ? "" : "");
    });
    var advisory = TOTAL_BY_SEV.major + TOTAL_BY_SEV.minor;
    return "Fails on " + parts.join(" + ") + " finding" + (blockers.length === 1 ? "" : "s") +
      ' · <span style="color:var(--text-3)">' + advisory + " advisory not blocking</span>";
  }

  function setGrouping(g) {
    if (S.grouping === g) return;
    S.grouping = g;
    document.querySelectorAll(".seg-btn").forEach(function (b) {
      var on = b.getAttribute("data-group") === g;
      b.setAttribute("aria-checked", String(on));
    });
    resetPaging();
    render();
  }

  function updateCounter(n) {
    var c = document.getElementById("counter");
    c.innerHTML = "Showing <b>" + n + "</b> of <b>" + TOTAL + "</b> findings";
  }

  /* ---------- init ---------- */
  buildHeader();
  render();
})();
