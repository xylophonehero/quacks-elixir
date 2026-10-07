/* Code excerpts from the repo, with a tiny Elixir highlighter.

   Markup:
     <figure class="excerpt" data-path="lib/quacks/game.ex" data-start="646" data-hl="649-650">
       <pre><code>...escaped source...</code></pre>
     </figure>

   data-path   repo path; adds the caption and a GitHub link (staging branch)
   data-start  first line number (default 1); the link covers start..last line
   data-hl     lines to tint, e.g. "649-650,653"
   data-label  caption text when there is no path (an iex session, a sketch)
   class "plain" hides the line numbers.
   Without JS the code still shows as a plain block. */
(function () {
  var REPO = "https://github.com/xylophonehero/quacks-elixir/blob/staging/";

  var KW = /^(def|defp|defmodule|defstruct|defmacro|do|end|fn|case|cond|with|if|else|unless|when|in|not|and|or|true|false|nil|use|alias|import|require|rescue|catch|for|after|receive)$/;

  var RULES = [
    ["com", /#.*/y],
    ["str", /"(?:\\.|[^"\\])*"?/y],
    ["atom", /:"[^"]*"/y],
    ["atom", /:(?![:\s])[a-zA-Z_][\w]*[?!]?/y],
    ["atom", /[a-z_][\w]*[?!]?:(?=\s)/y],
    ["mod", /[A-Z][\w]*(?:\.[A-Z][\w]*)*/y],
    ["attr", /@[a-z_]\w*/y],
    ["num", /\d[\d_]*(?:\.\d+)?/y],
    ["op", /\|>|<-|->|=>|\\\\|::|\+\+|==|!=|&&|\|\||\^|&(?=\d|%|[A-Za-z(])/y],
    ["id", /[a-z_][\w]*[?!]?/y]
  ];

  function esc(s) {
    return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  }

  function highlightLine(line) {
    var out = "";
    var i = 0;
    var plain = "";
    while (i < line.length) {
      var hit = null;
      for (var r = 0; r < RULES.length; r++) {
        var re = RULES[r][1];
        re.lastIndex = i;
        var m = re.exec(line);
        if (m && m[0].length) { hit = [RULES[r][0], m[0]]; break; }
      }
      // An atom or key must not start in the middle of a word (a::b, foo:bar).
      if (hit && hit[0] === "atom" && hit[1][0] === ":" && i > 0 && /[\w:]/.test(line[i - 1])) hit = null;
      if (!hit) { plain += line[i]; i++; continue; }
      if (plain) { out += esc(plain); plain = ""; }
      var cls = hit[0];
      var text = hit[1];
      if (cls === "id") cls = KW.test(text) ? "kw" : null;
      out += cls ? '<span class="tok-' + cls + '">' + esc(text) + "</span>" : esc(text);
      i += text.length;
    }
    if (plain) out += esc(plain);
    return out;
  }

  function parseRanges(s) {
    var set = {};
    (s || "").split(",").forEach(function (part) {
      var m = part.trim().match(/^(\d+)(?:-(\d+))?$/);
      if (!m) return;
      var a = +m[1], b = m[2] ? +m[2] : a;
      for (var n = a; n <= b; n++) set[n] = true;
    });
    return set;
  }

  function enhance(fig) {
    if (fig.dataset.ready) return;
    fig.dataset.ready = "1";
    var code = fig.querySelector("code");
    if (!code) return;
    var lines = code.textContent.replace(/^\n/, "").replace(/\s+$/, "").split("\n");
    var start = parseInt(fig.dataset.start || "1", 10);
    var hl = parseRanges(fig.dataset.hl);
    code.innerHTML = lines.map(function (l, k) {
      var n = start + k;
      return '<span class="ln' + (hl[n] ? " hl" : "") + '" data-n="' + n + '">' + (highlightLine(l) || " ") + "</span>";
    }).join("");

    var path = fig.dataset.path;
    var label = fig.dataset.label;
    if (!path && !label) return;
    var cap = document.createElement("figcaption");
    if (path) {
      var end = start + lines.length - 1;
      var p = document.createElement("span");
      p.className = "path";
      p.textContent = path;
      var r = document.createElement("span");
      r.className = "range";
      r.textContent = start === end ? "L" + start : "L" + start + "\u2013" + end;
      var a = document.createElement("a");
      a.href = REPO + path + "#L" + start + (end > start ? "-L" + end : "");
      a.target = "_blank";
      a.rel = "noopener";
      a.textContent = "GitHub";
      a.setAttribute("aria-label", "Open " + path + " on GitHub");
      cap.append(p, r, a);
    } else {
      cap.textContent = label;
    }
    fig.insertBefore(cap, fig.firstChild);
  }

  function run(root) {
    (root || document).querySelectorAll("figure.excerpt").forEach(enhance);
  }

  window.QES = window.QES || {};
  window.QES.code = { run: run, highlightLine: highlightLine };

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", function () { run(); });
  else run();
})();
