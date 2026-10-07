# Mission: Elixir and Phoenix, through the Quacks codebase

## Why
Nick is a frontend engineer (React, TypeScript, a Ruby full-stack app at work) who directs agents that build Quacks. He wants to read, review and steer that work with real understanding: why the code is shaped the way it is, how a tap in the browser becomes a game move and comes back, and what it costs to run.

## Success looks like
- Trace one player action end to end (browser, LiveView process, GameServer, `Game.apply/3`, PubSub, diff back to every tab) and name each hop.
- Read an engine function and explain its pattern matching, `with` chains and the RNG kept in the struct.
- Explain why there is one process per game and what happens when it crashes.
- Say what LiveView sends over the wire and spot a change that would make the payload or memory balloon.
- Describe the machine Quacks runs on, and what has to change to run on two or more machines.
- Review a builder's PR and catch one real design problem.

## Constraints
- Learns mostly on a phone, in short sessions: lessons must work at phone width and take about 10 minutes.
- Knows React well, so lessons map new ideas onto React and browser ideas.
- The existing guide (`docs/GUIDE.md`, `docs/guide/`) is the backbone; lessons point into it and into real code rather than toy examples.

## Out of scope
- Ecto and databases (Quacks has none).
- Writing Elixir from scratch at speed; the goal is reading, reviewing and steering.
- The full rulebook of the board game.
