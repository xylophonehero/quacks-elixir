#!/usr/bin/env bash
# Installs Erlang/OTP and Elixir in a Claude Code cloud container (Ubuntu 24.04),
# matching the versions CI uses (.github/workflows/ci.yml), then fetches deps.
# Needs these hosts allowed in the environment's network access:
#   builds.hex.pm, repo.hex.pm, hex.pm (github.com is allowed by default).
# Idempotent: a second run only checks the versions and returns.
set -euo pipefail

OTP_VERSION="${OTP_VERSION:-27.3}"
ELIXIR_VERSION="${ELIXIR_VERSION:-1.18.3}"
OTP_MAJOR="${OTP_VERSION%%.*}"
PREFIX="${BEAM_PREFIX:-/opt/beam}"

if [ ! -x "$PREFIX/otp/bin/erl" ]; then
  mkdir -p "$PREFIX/otp"
  curl -fsSL "https://builds.hex.pm/builds/otp/ubuntu-24.04/OTP-${OTP_VERSION}.tar.gz" |
    tar -xz -C "$PREFIX/otp" --strip-components=1
  "$PREFIX/otp/Install" -minimal "$PREFIX/otp" >/dev/null
fi

if [ ! -x "$PREFIX/elixir/bin/elixir" ]; then
  mkdir -p "$PREFIX/elixir"
  curl -fsSL -o "$PREFIX/elixir.zip" \
    "https://github.com/elixir-lang/elixir/releases/download/v${ELIXIR_VERSION}/elixir-otp-${OTP_MAJOR}.zip"
  unzip -qo "$PREFIX/elixir.zip" -d "$PREFIX/elixir" && rm "$PREFIX/elixir.zip"
fi

export PATH="$PREFIX/otp/bin:$PREFIX/elixir/bin:$PATH"

# Later shells (and Claude's Bash tool) pick the toolchain up from here.
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "export PATH=\"$PREFIX/otp/bin:$PREFIX/elixir/bin:\$PATH\"" >>"$CLAUDE_ENV_FILE"
fi
grep -qs "$PREFIX/elixir/bin" ~/.bashrc ||
  echo "export PATH=\"$PREFIX/otp/bin:$PREFIX/elixir/bin:\$PATH\"" >>~/.bashrc

mix local.hex --force --if-missing >/dev/null
mix local.rebar --force --if-missing >/dev/null

cd "${CLAUDE_PROJECT_DIR:-$(dirname "$0")/..}"
mix deps.get >/dev/null
MIX_ENV=test mix compile >/dev/null

elixir --version | tail -1
