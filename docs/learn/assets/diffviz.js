/* Diff visualizer: what LiveView sends for a template, step by step.

   Markup:
     <section class="diffviz" data-diff="diff-bar" aria-label="..."></section>
     <script type="application/json" id="diff-bar">{
       "template": "<p>«0»</p>",            static text with «n» marking dynamic slot n
       "slots": ["@title"],                  the expression behind each slot
       "steps": [
         { "label": "First load", "wire": "html", "payload": "<p>Hi</p>",
           "changed": [], "note": "html" },
         { "label": "Mount", "payload": {"s": ["<p>", "</p>"], "0": "Hi"},
           "changed": [0], "note": "html" }
       ]
     }</script>

   "payload" is a string (sent as is) or JSON (pretty-printed). "wire" is
   "html", "json" (default) or "sketch" (an illustration, not the exact frame). Its size shows in
   bytes, counted as UTF-8 of the compact form. Without JS nothing renders, so
   put a plain fallback inside the section if it matters. */
(function () {
  function el(tag, cls, text) {
    var e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text != null) e.textContent = text;
    return e;
  }

  function bytes(s) {
    try { return new TextEncoder().encode(s).length; } catch (e) { return s.length; }
  }

  function init(host) {
    if (host.dataset.ready) return;
    var data;
    try {
      data = JSON.parse(document.getElementById(host.dataset.diff).textContent);
    } catch (e) {
      return;
    }
    host.dataset.ready = "1";
    host.innerHTML = "";

    var tabs = el("div", "dv-steps");
    tabs.setAttribute("role", "group");
    tabs.setAttribute("aria-label", "Moments");
    var tplWrap = el("figure", "excerpt plain dv-template");
    var tplCap = el("figcaption", null, "Template, dynamic slots numbered");
    var tplPre = el("pre");
    var tplCode = el("code");
    tplPre.appendChild(tplCode);
    tplWrap.append(tplCap, tplPre);

    var legend = el("ol", "dv-legend");
    legend.start = 0;
    var note = el("p", "dv-note");
    note.setAttribute("aria-live", "polite");
    var payWrap = el("figure", "excerpt plain dv-payload");
    var payCap = el("figcaption");
    var payPre = el("pre");
    var payCode = el("code");
    payPre.appendChild(payCode);
    payWrap.append(payCap, payPre);

    // Template with slot markers.
    var parts = data.template.split(/«(\d+)»/);
    var slotEls = {};
    parts.forEach(function (part, i) {
      if (i % 2 === 0) {
        tplCode.appendChild(document.createTextNode(part));
      } else {
        var s = el("span", "dv-slot", part);
        s.dataset.slot = part;
        (slotEls[part] = slotEls[part] || []).push(s);
        tplCode.appendChild(s);
      }
    });
    var legendEls = {};
    data.slots.forEach(function (expr, i) {
      var li = el("li");
      var b = el("span", "dv-slot", String(i));
      var c = el("code", null, expr);
      li.append(b, " ", c);
      legendEls[i] = li;
      legend.appendChild(li);
    });

    var buttons = [];
    function show(k) {
      var step = data.steps[k];
      buttons.forEach(function (b, j) { b.setAttribute("aria-pressed", j === k ? "true" : "false"); });
      var changed = {};
      (step.changed || []).forEach(function (n) { changed[String(n)] = true; });
      Object.keys(slotEls).forEach(function (n) {
        slotEls[n].forEach(function (s) { s.classList.toggle("is-on", !!changed[n]); });
      });
      Object.keys(legendEls).forEach(function (n) { legendEls[n].classList.toggle("is-on", !!changed[n]); });
      var isText = typeof step.payload === "string";
      var compact = isText ? step.payload : JSON.stringify(step.payload);
      payCode.textContent = isText ? step.payload : JSON.stringify(step.payload, null, 1);
      var size = bytes(compact);
      var kind = step.wire === "html" ? "HTML over HTTP" : step.wire === "sketch" ? "Sketch, not the exact frame" : "JSON over the websocket";
      payCap.textContent = kind + " \u00b7 " + size + " bytes";
      note.innerHTML = step.note || "";
    }

    data.steps.forEach(function (step, k) {
      var b = el("button", "btn dv-step", step.label);
      b.type = "button";
      b.addEventListener("click", function () { show(k); });
      buttons.push(b);
      tabs.appendChild(b);
    });

    host.append(tabs, tplWrap, legend, note, payWrap);
    show(0);
  }

  function run(root) {
    (root || document).querySelectorAll(".diffviz[data-diff]").forEach(init);
  }

  window.QES = window.QES || {};
  window.QES.diffviz = { run: run };

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", function () { run(); });
  else run();
})();
