/* Per-lesson progress, kept in this browser only.
   Every storage access is wrapped: in a private window or a preview the store
   can throw or come back empty, and the pages still work without it. */
(function () {
  var KEY = "qes:progress:v1";
  var memory = {};

  function read() {
    try {
      var raw = window.localStorage.getItem(KEY);
      var data = raw ? JSON.parse(raw) : {};
      return data && typeof data === "object" ? data : {};
    } catch (e) {
      return memory;
    }
  }

  function write(data) {
    memory = data;
    try {
      window.localStorage.setItem(KEY, JSON.stringify(data));
    } catch (e) {
      /* storage blocked: keep the in-memory copy for this visit */
    }
  }

  function lesson(id) {
    var all = read();
    return all[id] || { answers: {}, done: false };
  }

  function saveAnswer(id, qid, correct) {
    var all = read();
    var l = all[id] || { answers: {}, done: false };
    var prev = l.answers[qid];
    // First try decides "right first time"; later tries only mark it answered.
    l.answers[qid] = { first: prev ? prev.first : correct, ever: (prev && prev.ever) || correct };
    l.seen = Date.now();
    all[id] = l;
    write(all);
    return l;
  }

  function markDone(id, total) {
    var all = read();
    var l = all[id] || { answers: {}, done: false };
    l.done = true;
    l.total = total;
    all[id] = l;
    write(all);
  }

  function reset(id) {
    var all = read();
    delete all[id];
    write(all);
  }

  /* "new" | "started" | "done" */
  function status(id) {
    var l = read()[id];
    if (!l) return "new";
    if (l.done) return "done";
    return Object.keys(l.answers || {}).length ? "started" : "new";
  }

  window.QES = window.QES || {};
  window.QES.progress = { lesson: lesson, saveAnswer: saveAnswer, markDone: markDone, reset: reset, status: status };
})();
