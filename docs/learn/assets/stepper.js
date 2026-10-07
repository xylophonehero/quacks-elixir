/* Step-through diagram.

   Markup:
     <section class="stepper" id="trip">
       <svg> ... any element with data-hop="2 3" lights up on steps 2 and 3 ... </svg>
       <div class="controls">
         <button class="btn" data-act="prev">Back</button>
         <span class="count" aria-live="polite"></span>
         <button class="btn primary" data-act="next">Next</button>
       </div>
       <ol class="panels"><li class="panel" data-step="1">...</li> ...</ol>
     </section>

   Without JS every panel shows, one after the other, and the controls hide. */
(function () {
  function init(root) {
    if (root.classList.contains("js")) return;
    var panels = Array.prototype.slice.call(root.querySelectorAll(".panel[data-step]"));
    if (!panels.length) return;
    var lit = root.querySelectorAll("[data-hop]");
    var prev = root.querySelector('[data-act="prev"]');
    var next = root.querySelector('[data-act="next"]');
    var count = root.querySelector(".count");
    var total = panels.length;
    var current = 1;

    function show(n) {
      current = Math.max(1, Math.min(total, n));
      panels.forEach(function (p) {
        var on = +p.dataset.step === current;
        p.classList.toggle("is-current", on);
        p.setAttribute("aria-hidden", on ? "false" : "true");
      });
      lit.forEach(function (el) {
        var hops = el.getAttribute("data-hop").split(/\s+/).map(Number);
        el.classList.toggle("is-on", hops.indexOf(current) !== -1);
      });
      if (count) count.textContent = "Hop " + current + " of " + total;
      if (prev) prev.disabled = current === 1;
      if (next) next.textContent = current === total ? "Start again" : "Next";
      root.dispatchEvent(new CustomEvent("stepper:change", { detail: { step: current, total: total } }));
    }

    if (prev) prev.addEventListener("click", function () { show(current - 1); });
    if (next) next.addEventListener("click", function () { show(current === total ? 1 : current + 1); });
    root.addEventListener("keydown", function (e) {
      if (e.target.closest && e.target.closest("input, textarea")) return;
      if (e.key === "ArrowRight") { show(current + 1); e.preventDefault(); }
      if (e.key === "ArrowLeft") { show(current - 1); e.preventDefault(); }
    });

    root.classList.add("js");
    show(1);
  }

  function run(root) {
    (root || document).querySelectorAll(".stepper").forEach(init);
  }

  window.QES = window.QES || {};
  window.QES.stepper = { run: run };

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", function () { run(); });
  else run();
})();
