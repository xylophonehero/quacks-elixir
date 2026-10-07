# Notes

## Preferences

- Learns on a phone, in sessions of about 10 minutes. Every page must work at 390px wide, with tap targets of 44px or more.
- Maps new ideas onto React and the browser. Each lesson gives the React equivalent as a margin note ("React ≈").
- Prefers real code from this repo over toy examples. Excerpts link to the `staging` branch on GitHub with line ranges; check line numbers against `lib/` before each lesson, because the guide's numbers drift.

## Working notes

- Lessons are a guided path through `docs/GUIDE.md` and `docs/guide/`, not a rewrite of it.
- Shared components in `assets/`: `course.css`, `progress.js` (localStorage, optional), `code.js` (excerpt + Elixir highlighter), `stepper.js` (step-through diagram), `quiz.js` (choice and type-the-answer items), `diffviz.js` (template slots and the diff per moment; reuse in lesson 7). `course.css` also has `.lab` styles for simulators.
- Quiz options in one question have the same word count; vary the correct position.
- The hub (`index.html`) is published inside a skeleton: no doctype, html, head or body tags there. Every other page is a full document.
- 2026-10-07: wants to keep going straight into the next lessons; enjoys seeing real repo code pattern-matched. Network settings for installing Elixir are parked (he is unsure how to change them); lessons must not depend on running Elixir.
- Lesson-specific simulators stay inline in their lesson: the mailbox (0003) and the supervision tree (0005). Move one to `assets/` when a later lesson needs it (0009 may reuse the tree).
- Each quiz from lesson 3 on interleaves one or two questions from earlier lessons.
