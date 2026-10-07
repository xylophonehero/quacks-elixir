/* Retrieval quiz with immediate feedback.

   Markup:
     <div class="quiz" data-quiz="quiz-0001" data-lesson="0001"></div>
     <script type="application/json" id="quiz-0001">{ "items": [ ... ] }</script>

   Item kinds:
     { "id": "q1", "q": "<html prompt>", "options": [{"t": "text", "why": "html"}, ...], "answer": 2 }
     { "id": "q2", "kind": "type", "q": "<html prompt>", "accept": ["legal_actions"],
       "answer": "legal_actions/2", "why": "html", "placeholder": "function name" }
   Either kind may carry "code": {"path": "...", "start": 1, "hl": "3", "src": "..."}
   (or "label" instead of "path"), shown with the excerpt component.

   Progress goes through QES.progress (localStorage, optional). The questions
   always start fresh: answering again is the practice. */
(function () {
  var LETTERS = "ABCDEFGH";

  function el(tag, cls, html) {
    var e = document.createElement(tag);
    if (cls) e.className = cls;
    if (html != null) e.innerHTML = html;
    return e;
  }

  function codeBlock(c) {
    var fig = el("figure", "excerpt" + (c.plain ? " plain" : ""));
    if (c.path) fig.dataset.path = c.path;
    if (c.label) fig.dataset.label = c.label;
    if (c.start) fig.dataset.start = String(c.start);
    if (c.hl) fig.dataset.hl = c.hl;
    var pre = el("pre");
    var code = el("code");
    code.textContent = c.src;
    pre.appendChild(code);
    fig.appendChild(pre);
    return fig;
  }

  function norm(s) {
    return String(s).toLowerCase().replace(/[`\s]/g, "").replace(/^quacks\./, "");
  }

  function init(host) {
    if (host.dataset.ready) return;
    host.dataset.ready = "1";
    var data;
    try {
      data = JSON.parse(document.getElementById(host.dataset.quiz).textContent);
    } catch (e) {
      host.textContent = "The quiz could not load.";
      return;
    }
    var lesson = host.dataset.lesson || host.dataset.quiz;
    var store = window.QES && window.QES.progress;
    var items = data.items;
    var state = {}; // id -> { first: bool, settled: bool }

    var scoreMsg = el("p", "msg");
    var resetBtn = el("button", "btn", "Clear my answers");
    resetBtn.type = "button";

    // correct: this attempt was right. isFirst: it was the first attempt.
    function settle(item, correct, isFirst) {
      var s = state[item.id] || (state[item.id] = { first: correct && isFirst, settled: false });
      if (correct || item.revealed) s.settled = true;
      if (store) store.saveAnswer(lesson, item.id, correct);
      updateScore();
    }

    function updateScore() {
      var answered = 0, first = 0;
      items.forEach(function (it) {
        var s = state[it.id];
        if (s && s.settled) answered++;
        if (s && s.first) first++;
      });
      if (answered === items.length) {
        scoreMsg.innerHTML = "<strong>" + first + " of " + items.length + "</strong> right on the first try. Lesson marked done.";
        if (store) store.markDone(lesson, items.length);
      } else {
        scoreMsg.textContent = answered + " of " + items.length + " answered.";
      }
    }

    items.forEach(function (item, idx) {
      var q = el("section", "q");
      q.id = (host.id || lesson) + "-" + item.id;
      var prompt = el("div", "q-prompt");
      var chip = el("span", "chip", String(idx + 1));
      chip.dataset.c = ["orange", "green", "blue", "red", "yellow", "purple"][idx % 6];
      chip.setAttribute("aria-hidden", "true");
      var p = el("p", null, item.q);
      prompt.append(chip, p);
      q.appendChild(prompt);
      if (item.code) q.appendChild(codeBlock(item.code));

      var fb = el("p", "q-feedback");
      fb.setAttribute("aria-live", "polite");

      if (item.kind === "type") {
        var row = el("div", "q-type");
        var input = el("input");
        input.type = "text";
        input.id = q.id + "-input";
        input.autocomplete = "off";
        input.autocapitalize = "off";
        input.spellcheck = false;
        input.placeholder = item.placeholder || "Type your answer";
        input.setAttribute("aria-label", "Your answer");
        var check = el("button", "btn primary", "Check");
        check.type = "button";
        var show = el("button", "btn", "Show answer");
        show.type = "button";
        row.append(input, check, show);
        q.appendChild(row);
        q.appendChild(fb);
        var accept = (item.accept || []).map(norm);
        var tried = false;
        var doCheck = function () {
          var v = norm(input.value);
          if (!v) { input.focus(); return; }
          var ok = accept.indexOf(v) !== -1;
          fb.className = "q-feedback " + (ok ? "right" : "wrong");
          fb.innerHTML = ok
            ? '<span class="verdict">Right.</span> ' + (item.why || "")
            : '<span class="verdict">Not yet.</span> Try again, or tap Show answer.';
          if (!tried || ok) settle(item, ok, !tried);
          if (ok) { input.disabled = true; check.disabled = true; show.disabled = true; }
          tried = true;
        };
        check.addEventListener("click", doCheck);
        input.addEventListener("keydown", function (e) { if (e.key === "Enter") { e.preventDefault(); doCheck(); } });
        show.addEventListener("click", function () {
          item.revealed = true;
          fb.className = "q-feedback wrong";
          fb.innerHTML = '<span class="verdict">Answer: <code></code>.</span> ' + (item.why || "");
          fb.querySelector("code").textContent = item.answer;
          input.disabled = true; check.disabled = true; show.disabled = true;
          settle(item, false, !tried);
          tried = true;
        });
      } else {
        var list = el("ul", "q-options");
        var buttons = [];
        var done = false;
        var firstTry = true;
        item.options.forEach(function (opt, k) {
          var li = el("li");
          var b = el("button", "q-opt");
          b.type = "button";
          b.setAttribute("aria-pressed", "false");
          var key = el("span", "k", LETTERS[k]);
          var t = el("span");
          t.textContent = opt.t;
          b.append(key, t);
          b.addEventListener("click", function () {
            if (done) return;
            var ok = k === item.answer;
            buttons.forEach(function (o) { o.setAttribute("aria-pressed", "false"); o.classList.remove("right", "wrong"); });
            b.setAttribute("aria-pressed", "true");
            b.classList.add(ok ? "right" : "wrong");
            fb.className = "q-feedback " + (ok ? "right" : "wrong");
            fb.innerHTML = '<span class="verdict">' + (ok ? "Right." : "Not quite.") + "</span> " + (opt.why || "") +
              (ok ? "" : " Try another answer.");
            if (firstTry || ok) settle(item, ok, firstTry);
            firstTry = false;
            if (ok) {
              done = true;
              buttons.forEach(function (o) { if (o !== b) o.disabled = true; });
            }
          });
          buttons.push(b);
          li.appendChild(b);
          list.appendChild(li);
        });
        q.appendChild(list);
        q.appendChild(fb);
      }
      host.appendChild(q);
    });

    var score = el("div", "score");
    score.append(scoreMsg, resetBtn);
    host.appendChild(score);
    resetBtn.addEventListener("click", function () {
      if (store) store.reset(lesson);
      host.innerHTML = "";
      delete host.dataset.ready;
      items.forEach(function (it) { delete it.revealed; });
      init(host);
      var first = host.querySelector("button, input");
      if (first) first.focus();
    });

    var before = store ? store.status(lesson) : "new";
    updateScore();
    if (before === "done") scoreMsg.textContent += " You finished this lesson before; answer again for practice.";
    if (window.QES && window.QES.code) window.QES.code.run(host);
  }

  function run(root) {
    (root || document).querySelectorAll(".quiz[data-quiz]").forEach(init);
  }

  window.QES = window.QES || {};
  window.QES.quiz = { run: run };

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", function () { run(); });
  else run();
})();
