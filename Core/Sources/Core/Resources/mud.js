// Mud - Shared client-side helpers (find, scroll, zoom).
// Exposed on window.Mud; called from Swift via evaluateJavaScript.

(function () {
  "use strict";

  // -- Self-inject styles (not in CSS files — kept out of HTML exports) -----

  var STYLE = document.createElement("style");
  STYLE.textContent =
    "mark.mud-match{background-color:#fde68a;color:inherit;border-radius:2px}" +
    "mark.mud-match-active{background-color:#f59e0b;outline:2px solid #d97706;outline-offset:-1px}" +
    "@media(prefers-color-scheme:dark){" +
    "mark.mud-match{background-color:rgba(253,230,138,0.3)}" +
    "mark.mud-match-active{background-color:rgba(245,158,11,0.5);outline-color:rgba(217,119,6,0.7)}" +
    "}";
  document.head.appendChild(STYLE);

  function CONTAINER() {
    return document.querySelector(".up-mode-output")
        ? ".up-mode-output"
        : ".down-mode-output";
  }
  var MATCH_CLASS = "mud-match";
  var ACTIVE_CLASS = "mud-match-active";

  var marks = [];       // current <mark> elements in DOM order
  var activeIndex = -1; // index of the currently-active match

  // -- Highlight helpers ---------------------------------------------------

  // Walk all text nodes inside the container, split at case-insensitive
  // matches, and wrap each match in <mark class="mud-match">.
  function highlightAll(text) {
    clearHighlights();
    if (!text) return;

    var container = document.querySelector(CONTAINER());
    if (!container) return;

    var pattern = new RegExp(
      text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"),
      "gi"
    );

    // Collect text nodes first (mutating the DOM while walking is unsafe).
    var walker = document.createTreeWalker(
      container,
      NodeFilter.SHOW_TEXT,
      null
    );
    var nodes = [];
    var node;
    while ((node = walker.nextNode())) nodes.push(node);

    for (var i = 0; i < nodes.length; i++) {
      var textNode = nodes[i];
      var value = textNode.nodeValue;
      var match;
      var lastIndex = 0;
      var parts = [];
      pattern.lastIndex = 0;

      while ((match = pattern.exec(value)) !== null) {
        if (match.index > lastIndex) {
          parts.push(document.createTextNode(
            value.slice(lastIndex, match.index)
          ));
        }
        var mark = document.createElement("mark");
        mark.className = MATCH_CLASS;
        mark.textContent = match[0];
        parts.push(mark);
        lastIndex = pattern.lastIndex;
        // Guard against zero-length matches.
        if (match[0].length === 0) pattern.lastIndex++;
      }

      if (parts.length === 0) continue;

      if (lastIndex < value.length) {
        parts.push(document.createTextNode(value.slice(lastIndex)));
      }

      var parent = textNode.parentNode;
      for (var j = 0; j < parts.length; j++) {
        parent.insertBefore(parts[j], textNode);
      }
      parent.removeChild(textNode);
    }

    marks = Array.prototype.slice.call(
      container.querySelectorAll("mark." + MATCH_CLASS)
    );
  }

  function activateMatch(n) {
    if (marks.length === 0) return;
    if (activeIndex >= 0 && activeIndex < marks.length) {
      marks[activeIndex].classList.remove(ACTIVE_CLASS);
    }
    activeIndex = ((n % marks.length) + marks.length) % marks.length;
    var el = marks[activeIndex];
    el.classList.add(ACTIVE_CLASS);
    el.scrollIntoView({ block: "center", behavior: "smooth" });
  }

  function clearHighlights() {
    for (var i = 0; i < marks.length; i++) {
      var mark = marks[i];
      var parent = mark.parentNode;
      if (!parent) continue;
      parent.replaceChild(document.createTextNode(mark.textContent), mark);
      parent.normalize();
    }
    marks = [];
    activeIndex = -1;
  }

  function result() {
    return { total: marks.length, current: activeIndex + 1 };
  }

  // -- Find API ------------------------------------------------------------

  function findFromTop(text) {
    highlightAll(text);
    if (marks.length > 0) activateMatch(0);
    return result();
  }

  function findRefine(text) {
    // Remember the active match's viewport position so we can pick the
    // nearest match after re-highlighting.
    var refY = null;
    if (activeIndex >= 0 && activeIndex < marks.length) {
      refY = marks[activeIndex].getBoundingClientRect().top;
    }

    highlightAll(text);

    if (marks.length === 0) return result();

    if (refY !== null) {
      // Pick the match closest to the previous active position.
      var best = 0;
      var bestDist = Infinity;
      for (var i = 0; i < marks.length; i++) {
        var d = Math.abs(marks[i].getBoundingClientRect().top - refY);
        if (d < bestDist) { bestDist = d; best = i; }
      }
      activateMatch(best);
    } else {
      activateMatch(0);
    }
    return result();
  }

  function findAdvance(text, direction) {
    // If highlights are stale or absent, rebuild them.
    if (marks.length === 0) {
      highlightAll(text);
      if (marks.length === 0) return result();
      activateMatch(0);
      return result();
    }

    var delta = direction === "backward" ? -1 : 1;
    activateMatch(activeIndex + delta);
    return result();
  }

  function findClear() {
    clearHighlights();
  }

  // -- Scroll --------------------------------------------------------------

  function getScrollY() {
    return window.scrollY;
  }

  function setScrollY(y) {
    window.scrollTo(0, y);
  }

  function getScrollFraction() {
    var maxScroll = document.documentElement.scrollHeight - window.innerHeight;
    if (maxScroll <= 0) return 0;
    return window.scrollY / maxScroll;
  }

  function setScrollFraction(f) {
    var maxScroll = document.documentElement.scrollHeight - window.innerHeight;
    window.scrollTo(0, f * maxScroll);
  }

  // -- Outline navigation ---------------------------------------------------

  function scrollToHeading(slug) {
    var el = document.getElementById(slug);
    if (el) el.scrollIntoView({ behavior: "smooth", block: "start" });
  }

  function scrollToLine(lineNumber) {
    var lines = document.querySelectorAll(".down-lines .dl");
    var idx = lineNumber - 1;
    if (idx >= 0 && idx < lines.length) {
      lines[idx].scrollIntoView({ behavior: "smooth", block: "start" });
    }
  }

  // -- Change tracking: overlays --------------------------------------------

  var _overlays = {};       // groupID → overlay element
  var _expandedGroups = {}; // groupID → true when expanded
  var _groupTypes = {};     // groupID → "ins" | "del" | "mix"

  // Sub-overlays: temporary red/green overlays created when a mixed
  // (blue) group is expanded. Each entry: { overlay, els, groupId }.
  var _subOverlays = [];
  // Group IDs whose original overlay is suppressed (replaced by sub-overlays).
  var _suppressedGroups = {};

  function buildOverlays() {
    var container = document.querySelector(".up-mode-output");
    if (!container) return;

    // Remove any existing overlays.
    var old = container.querySelectorAll(".mud-overlay");
    for (var i = 0; i < old.length; i++) old[i].remove();
    _overlays = {};
    _expandedGroups = {};
    _groupTypes = {};
    _subOverlays = [];
    _suppressedGroups = {};

    // Discover groups from data-group-id attributes.
    var els = container.querySelectorAll("[data-group-id]");
    var groups = {};  // groupID → { index, hasDel, hasIns }
    for (var j = 0; j < els.length; j++) {
      var gid = els[j].dataset.groupId;
      if (!groups[gid]) {
        groups[gid] = {
          index: els[j].dataset.groupIndex || "",
          hasDel: false,
          hasIns: false
        };
      }
      if (els[j].classList.contains("mud-change-del")
          || els[j].classList.contains("cl-del")) {
        groups[gid].hasDel = true;
      } else {
        groups[gid].hasIns = true;
      }
    }

    // Create one overlay per group.
    for (var gid in groups) {
      var g = groups[gid];
      var type = (g.hasDel && g.hasIns) ? "mix"
               : g.hasIns ? "ins" : "del";
      var typeClass = "mud-overlay-" + type;
      _groupTypes[gid] = type;

      var div = document.createElement("div");
      div.className = "mud-overlay " + typeClass;
      div.dataset.groupId = gid;
      div.dataset.groupIndex = g.index;

      // Add expando button to every group.
      var btn = document.createElement("button");
      btn.className = "mud-expando";
      btn.textContent = g.index;
      div.appendChild(btn);

      if (type === "ins") {
        // Ins-only groups are always expanded; button is non-interactive.
        btn.classList.add("mud-expando-expanded");
        btn.disabled = true;
        btn.setAttribute("aria-expanded", "true");
      } else {
        btn.setAttribute("aria-expanded", "false");
        btn.addEventListener("click", (function (id) {
          return function () { toggleGroup(id); };
        })(gid));
      }

      // Del-only groups start collapsed.
      if (type === "del") {
        div.classList.add("mud-overlay-collapsed");
      }

      container.appendChild(div);
      _overlays[gid] = div;
    }

    positionOverlays();
  }

  /// Position an overlay element to span from the first to last
  /// visible element in `els`, relative to `container`.
  function positionOverlay(overlay, els, containerRect, scrollTop) {
    var visible = [];
    for (var i = 0; i < els.length; i++) {
      if (els[i].offsetParent !== null) visible.push(els[i]);
    }
    if (visible.length === 0) {
      overlay.style.display = "none";
      return;
    }
    var zoom = parseFloat(document.documentElement.style.zoom) || 1;
    var firstRect = visible[0].getBoundingClientRect();
    var lastRect = visible[visible.length - 1].getBoundingClientRect();
    overlay.style.display = "";
    overlay.style.top = ((firstRect.top - containerRect.top) / zoom + scrollTop) + "px";
    overlay.style.height = ((lastRect.bottom - firstRect.top) / zoom) + "px";
  }

  /// Position a collapsed del-only overlay at the gap where its
  /// hidden deletions would appear.
  function positionCollapsedOverlay(overlay, gid, container, containerRect, scrollTop) {
    var els = container.querySelectorAll(
      "[data-group-id='" + gid + "']:not(.mud-overlay)"
    );
    if (els.length === 0) {
      overlay.style.display = "none";
      return;
    }
    // Walk backwards from the first del element to find a visible sibling.
    var first = els[0];
    var prev = first.previousElementSibling;
    while (prev && prev.offsetParent === null) {
      prev = prev.previousElementSibling;
    }
    var zoom = parseFloat(document.documentElement.style.zoom) || 1;
    var top;
    if (prev) {
      var prevRect = prev.getBoundingClientRect();
      top = (prevRect.bottom - containerRect.top) / zoom + scrollTop;
    } else {
      top = 0;
    }
    overlay.style.display = "";
    overlay.style.top = top + "px";
  }

  function positionOverlays() {
    var container = document.querySelector(".up-mode-output");
    if (!container) return;
    var containerRect = container.getBoundingClientRect();
    var scrollTop = container.scrollTop;

    for (var gid in _overlays) {
      if (_suppressedGroups[gid]) continue;
      var overlay = _overlays[gid];

      if (overlay.classList.contains("mud-overlay-collapsed")) {
        positionCollapsedOverlay(overlay, gid, container, containerRect, scrollTop);
        continue;
      }

      var els = container.querySelectorAll(
        "[data-group-id='" + gid + "']:not(.mud-overlay)"
      );
      positionOverlay(overlay, els, containerRect, scrollTop);
    }

    for (var i = 0; i < _subOverlays.length; i++) {
      var sub = _subOverlays[i];
      positionOverlay(sub.overlay, sub.els, containerRect, scrollTop);
    }

    // Make consecutive sub-overlays for the same group continuous:
    // extend each overlay's bottom to meet the next overlay's top.
    // Mark non-last overlays as "cont" and last overlays as "tail".
    for (var i = 0; i < _subOverlays.length; i++) {
      var cur = _subOverlays[i];
      var next = _subOverlays[i + 1];
      var isLast = !next || next.groupId !== cur.groupId;
      cur.overlay.classList.toggle("mud-overlay-cont", !isLast);
      cur.overlay.classList.toggle("mud-overlay-tail", isLast);
      if (isLast) continue;
      if (cur.overlay.style.display === "none") continue;
      if (next.overlay.style.display === "none") continue;
      var curTop = parseFloat(cur.overlay.style.top);
      var nextTop = parseFloat(next.overlay.style.top);
      if (nextTop > curTop) {
        cur.overlay.style.height = (nextTop - curTop) + "px";
      }
    }
  }

  // Build overlays on load; reposition on resize.
  buildOverlays();
  var _upContainer = document.querySelector(".up-mode-output");
  if (_upContainer) {
    new ResizeObserver(positionOverlays).observe(_upContainer);
  }

  // -- Change tracking: expand / collapse -----------------------------------

  function expandGroup(gid) {
    _expandedGroups[gid] = true;
    var overlay = _overlays[gid];
    if (!overlay) return;
    var container = document.querySelector(".up-mode-output");
    var type = _groupTypes[gid];

    // Mark all elements in group as revealed.
    var els = container.querySelectorAll(
      "[data-group-id='" + gid + "']:not(.mud-overlay)"
    );
    for (var i = 0; i < els.length; i++) {
      els[i].classList.add("mud-change-revealed");
    }

    if (type === "del") {
      overlay.classList.remove("mud-overlay-collapsed");
      overlay.classList.add("mud-change-revealed");
    } else if (type === "mix") {
      // Hide blue overlay and create red/green sub-overlays.
      overlay.style.display = "none";
      _suppressedGroups[gid] = true;

      // Split group elements into consecutive runs by type.
      var runs = [];
      var cur = null;
      for (var k = 0; k < els.length; k++) {
        var t = (els[k].classList.contains("mud-change-del")
                 || els[k].classList.contains("cl-del")) ? "del" : "ins";
        if (cur && cur.type === t) {
          cur.els.push(els[k]);
        } else {
          cur = { type: t, els: [els[k]] };
          runs.push(cur);
        }
      }

      // Create a sub-overlay for each run, starting invisible.
      var firstSub = null;
      for (var r = 0; r < runs.length; r++) {
        var run = runs[r];
        var typeClass = run.type === "del"
          ? "mud-overlay-del" : "mud-overlay-ins";
        var div = document.createElement("div");
        div.className = "mud-overlay " + typeClass;
        div.dataset.groupId = gid;
        div.dataset.groupIndex = overlay.dataset.groupIndex;
        div.style.opacity = "0";
        div.setAttribute("aria-hidden", "true");
        container.appendChild(div);
        _subOverlays.push({
          overlay: div, els: run.els, groupId: gid
        });
        if (!firstSub) firstSub = div;
      }

      // Move button to first sub-overlay.
      var btn = overlay.querySelector(".mud-expando");
      if (btn && firstSub) {
        firstSub.appendChild(btn);
      }
    }

    // Mark button as expanded.
    var btn = overlay.querySelector(".mud-expando")
           || (container && container.querySelector(
                ".mud-overlay[data-group-id='" + gid + "'] .mud-expando"));
    if (btn) {
      btn.classList.add("mud-expando-expanded");
      btn.setAttribute("aria-expanded", "true");
    }

    positionOverlays();

    // Fade in sub-overlays on next frame.
    if (type === "mix") {
      requestAnimationFrame(function () {
        for (var i = 0; i < _subOverlays.length; i++) {
          if (_subOverlays[i].groupId === gid) {
            _subOverlays[i].overlay.style.opacity = "";
          }
        }
      });
    }
  }

  function collapseGroup(gid) {
    delete _expandedGroups[gid];
    var overlay = _overlays[gid];
    if (!overlay) return;
    var container = document.querySelector(".up-mode-output");
    var type = _groupTypes[gid];

    // Remove revealed class from all elements in group.
    var els = container.querySelectorAll(
      "[data-group-id='" + gid + "']:not(.mud-overlay)"
    );
    for (var i = 0; i < els.length; i++) {
      els[i].classList.remove("mud-change-revealed");
    }

    if (type === "del") {
      overlay.classList.add("mud-overlay-collapsed");
      overlay.classList.remove("mud-change-revealed");
    } else if (type === "mix") {
      // Move button back from sub-overlay, then remove sub-overlays.
      var remaining = [];
      for (var i = 0; i < _subOverlays.length; i++) {
        if (_subOverlays[i].groupId === gid) {
          var movedBtn = _subOverlays[i].overlay.querySelector(".mud-expando");
          if (movedBtn) overlay.appendChild(movedBtn);
          _subOverlays[i].overlay.remove();
        } else {
          remaining.push(_subOverlays[i]);
        }
      }
      _subOverlays = remaining;
      delete _suppressedGroups[gid];
      overlay.style.display = "";
    }

    // Unmark button.
    var btn = overlay.querySelector(".mud-expando");
    if (btn) {
      btn.classList.remove("mud-expando-expanded");
      btn.setAttribute("aria-expanded", "false");
    }

    positionOverlays();
  }

  function toggleGroup(gid) {
    if (_expandedGroups[gid]) {
      collapseGroup(gid);
    } else {
      expandGroup(gid);
    }
  }

  function collapseAllChanges() {
    for (var gid in _expandedGroups) {
      collapseGroup(gid);
    }
  }

  // -- Change tracking: scroll ----------------------------------------------

  function scrollToChange(ids) {
    if (!ids.length) return;
    var first = document.querySelector(
      '[data-change-id="' + ids[0] + '"]'
    );
    if (!first) return;
    var gid = first.dataset.groupId;

    // For collapsed del-only groups, scroll to the overlay button.
    if (first.offsetParent === null && gid && _overlays[gid]) {
      var btn = _overlays[gid].querySelector(".mud-expando");
      if (btn) {
        btn.scrollIntoView({ behavior: "smooth", block: "center" });
      }
    } else {
      first.scrollIntoView({ behavior: "smooth", block: "center" });
    }

    // Ripple the expando button for the group.
    if (!gid) return;

    // Clear any leftover active state from a previous navigation.
    var stale = document.querySelectorAll(".mud-expando.mud-change-active");
    for (var s = 0; s < stale.length; s++) {
      stale[s].classList.remove("mud-change-active");
    }

    var btn = null;
    if (_overlays[gid]) {
      btn = _overlays[gid].querySelector(".mud-expando");
    }
    if (!btn) {
      for (var i = 0; i < _subOverlays.length; i++) {
        if (_subOverlays[i].groupId === gid) {
          btn = _subOverlays[i].overlay.querySelector(".mud-expando");
          if (btn) break;
        }
      }
    }
    if (btn) {
      void btn.offsetWidth;
      btn.classList.add("mud-change-active");
      btn.addEventListener("animationend", function () {
        btn.classList.remove("mud-change-active");
      }, { once: true });
    }
  }

  // -- Body classes ---------------------------------------------------------

  function setClass(name, enabled) {
    if (enabled) {
      document.documentElement.classList.add(name);
    } else {
      document.documentElement.classList.remove(name);
    }
  }

  // -- Theme ----------------------------------------------------------------

  function setTheme(cssString) {
    var el = document.getElementById("mud-theme");
    if (el) el.textContent = cssString;
  }

  // -- Zoom ----------------------------------------------------------------

  function setZoom(level) {
    document.documentElement.style.zoom = level;
  }

  // -- Public namespace ----------------------------------------------------

  window.Mud = {
    findFromTop: findFromTop,
    findRefine: findRefine,
    findAdvance: findAdvance,
    findClear: findClear,
    getScrollY: getScrollY,
    setScrollY: setScrollY,
    getScrollFraction: getScrollFraction,
    setScrollFraction: setScrollFraction,
    setTheme: setTheme,
    setClass: setClass,
    setZoom: setZoom,
    scrollToHeading: scrollToHeading,
    scrollToLine: scrollToLine,
    scrollToChange: scrollToChange,
    collapseAllChanges: collapseAllChanges
  };
})();
