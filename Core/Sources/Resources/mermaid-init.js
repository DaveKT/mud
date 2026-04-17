// Mermaid diagram renderer for Up mode.
// Injected as a WKUserScript after mermaid.min.js.

(function () {
  if (!document.querySelector(".up-mode-output")) return;

  var theme = window.matchMedia("(prefers-color-scheme: dark)").matches
    ? "dark"
    : "default";

  mermaid.initialize({
    startOnLoad: false,
    securityLevel: "strict",
    theme: theme,
  });

  var nodes = [];
  document.querySelectorAll("code.language-mermaid").forEach(function (code) {
    var pre = code.parentElement;
    if (!pre || pre.tagName !== "PRE") return;

    // Skip deleted mermaid blocks (change tracking).
    if (pre.classList.contains("mud-change-del")) return;

    var container = document.createElement("div");
    container.className = "mermaid";
    container.textContent = code.textContent;

    // Preserve change-tracking attributes through the replacement.
    if (pre.dataset.changeId) {
      container.dataset.changeId = pre.dataset.changeId;
      container.dataset.groupId = pre.dataset.groupId;
      container.dataset.groupIndex = pre.dataset.groupIndex;
      pre.classList.forEach(function (cls) {
        if (cls.startsWith("mud-change-")) container.classList.add(cls);
      });
    }

    pre.parentNode.replaceChild(container, pre);
    nodes.push(container);
  });

  if (nodes.length > 0) {
    mermaid.run({ nodes: nodes });
  }
})();
