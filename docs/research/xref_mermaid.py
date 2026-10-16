"""Turn `mix xref graph --format dot` into the Mermaid graphs of
docs/research/architecture-review.md.

    mix xref graph --format dot --output xref.dot
    python3 docs/research/xref_mermaid.py xref.dot core   # engine, runtime, bots
    python3 docs/research/xref_mermaid.py xref.dot web    # web calls past the facade
"""
import os
import re
import sys

dot, mode = sys.argv[1], sys.argv[2]
edges = set()
for line in open(dot):
    m = re.match(r'\s*"([^"]+)" -> "([^"]+)"', line)
    if m:
        edges.add((m.group(1), m.group(2)))

module = {}
for path in {p for e in edges for p in e}:
    m = re.search(r"defmodule\s+([\w.]+)", open(path).read())
    module[path] = m.group(1) if m else path
edges = sorted({(module[a], module[b]) for a, b in edges if module[a] != module[b]})


def nid(m):
    return m.replace(".", "_")


groups = {
    "Engine": ["Quacks.Game", "Quacks.Game.Essence", "Quacks.Game.Evaluation",
               "Quacks.Game.Fortune", "Quacks.Game.Potions", "Quacks.Game.Witches",
               "Quacks.Player"],
    "Runtime": ["Quacks.Session", "Quacks.GameServer", "Quacks.GameStore",
                "Quacks.BugReports"],
    "Bots": ["Quacks.AI", "Quacks.AI.Decider", "Quacks.AI.Choice", "Quacks.AI.Expectimax",
             "Quacks.AI.Odds", "Quacks.AI.Shop", "Quacks.AI.Profile", "Quacks.AI.Names",
             "Quacks.AI.Bench", "Quacks.AI.Sim"],
    "Scenarios": ["Quacks.Scenarios", "Quacks.Scenarios.Builders", "Quacks.Scenarios.Script"],
}
past_facade = {"Quacks.Game.Essence", "Quacks.Game.Evaluation", "Quacks.Game.Fortune",
               "Quacks.Game.Potions", "Quacks.Game.Witches", "Quacks.AI.Odds",
               "Quacks.GameServer"}

out = ["flowchart LR"]
if mode == "core":
    keep = {m for ms in groups.values() for m in ms}
    for name, ms in groups.items():
        out.append(f"  subgraph {name}")
        out += [f'    {nid(m)}["{m}"]' for m in ms]
        out.append("  end")
    out += [f"  {nid(a)} --> {nid(b)}" for a, b in edges if a in keep and b in keep]
else:
    web = sorted({a for a, b in edges if a.startswith("QuacksWeb") and b in past_facade})
    out.append("  subgraph Web")
    out += [f'    {nid(m)}["{m}"]' for m in web]
    out.append("  end")
    out.append("  subgraph Core")
    out += [f'    {nid(m)}["{m}"]' for m in sorted(past_facade)]
    out.append("  end")
    out += [f"  {nid(a)} --> {nid(b)}" for a, b in edges if a in web and b in past_facade]
print("\n".join(out))
