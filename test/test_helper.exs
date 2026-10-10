# The UI snapshots (`QuacksWeb.UiSnapshotTest`) run on their own:
# `mix test --only snapshot`; `mix precommit` runs them after the suite.
ExUnit.start(exclude: [:snapshot])
