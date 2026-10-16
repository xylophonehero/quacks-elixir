defmodule CodenamesDuetWeb.KeyContrastTest do
  @moduledoc """
  The key colours of the Duet cards (`assets/css/codenames.css`): the word on each
  fill has a contrast of 4.5:1 or more (WCAG AA) in every table theme. The test
  reads the `oklch()` token values from the CSS, so a change of a value is checked.
  """
  use ExUnit.Case, async: true

  alias TableWeb.Components.Theme

  @css Path.expand("../../assets/css/codenames.css", __DIR__)
  @table_css Path.expand("../../assets/css/table.css", __DIR__)

  # {fill, ink} pairs: the key tints, a found agent, a covered bystander.
  @pairs [
    {"agent", "agent-ink"},
    {"assassin", "assassin-ink"},
    {"bystander", "bystander-ink"},
    {"found", "found-ink"},
    {"covered", "covered-ink"}
  ]

  test "every word on a key fill has 4.5:1 or more in every theme" do
    for theme <- Theme.themes(), {fill, ink} <- @pairs do
      tokens = tokens(theme.dark)
      ratio = contrast(tokens[fill], tokens[ink])

      if System.get_env("CD_CONTRAST"),
        do: IO.puts("#{theme.id} #{fill}: #{Float.round(ratio, 2)}")

      assert ratio >= 4.5,
             "#{theme.id}: --cd-#{ink} on --cd-#{fill} is #{Float.round(ratio, 2)}:1"
    end
  end

  test "the fills differ from each other and from the plain card face" do
    for dark <- [false, true] do
      tokens = tokens(dark)
      face = card_face(dark)
      lum = Enum.map(~w(agent assassin bystander), &luminance(tokens[&1]))
      assert Enum.uniq(lum) == lum
      # The assassin is dark: 10:1 or more from the light card face.
      assert contrast(tokens["assassin"], face) >= 10
    end
  end

  test "the contrast maths: black on white is 21:1" do
    assert_in_delta contrast({1.0, 0.0, 0.0}, {0.0, 0.0, 0.0}), 21.0, 0.01
  end

  # -- the CSS -----------------------------------------------------------------------

  defp tokens(dark?) do
    css = File.read!(@css)
    [base | _] = Regex.run(~r/\.tb-root \{(.*?)\}/s, css, capture: :all_but_first)

    [dark | _] =
      Regex.run(~r/\.tb-root:is\(\[data-theme="dracula"\][^{]*\{(.*?)\}/s, css,
        capture: :all_but_first
      )

    base = parse(base)
    if dark?, do: Map.merge(base, parse(dark)), else: base
  end

  defp card_face(dark?) do
    css = File.read!(@table_css)
    [face] = Regex.run(~r/--tb-card-face: (oklch\([^)]*\))/, css, capture: :all_but_first)

    [dark_face] =
      Regex.run(~r/\[data-theme="night"\]\) \{.*?--tb-card-face: (oklch\([^)]*\))/s, css,
        capture: :all_but_first
      )

    oklch(if dark?, do: dark_face, else: face)
  end

  defp parse(block) do
    for [name, value] <-
          Regex.scan(~r/--cd-([a-z-]+): (oklch\([^)]*\));/, block, capture: :all_but_first),
        into: %{},
        do: {name, oklch(value)}
  end

  defp oklch(text) do
    [l, c, h] = Regex.run(~r/oklch\(([\d.]+)% ([\d.]+) ([\d.]+)/, text, capture: :all_but_first)
    {num(l) / 100, num(c), num(h)}
  end

  defp num(s), do: s |> Float.parse() |> elem(0)

  # -- the colour maths (OKLCH → linear sRGB → WCAG relative luminance) ----------------

  defp contrast(a, b) do
    [hi, lo] = Enum.sort([luminance(a), luminance(b)], :desc)
    (hi + 0.05) / (lo + 0.05)
  end

  defp luminance({l, c, h}) do
    rad = h * :math.pi() / 180
    a = c * :math.cos(rad)
    b = c * :math.sin(rad)

    l_ = :math.pow(l + 0.3963377774 * a + 0.2158037573 * b, 3)
    m_ = :math.pow(l - 0.1055613458 * a - 0.0638541728 * b, 3)
    s_ = :math.pow(l - 0.0894841775 * a - 1.2914855480 * b, 3)

    r = 4.0767416621 * l_ - 3.3077115913 * m_ + 0.2309699292 * s_
    g = -1.2684380046 * l_ + 2.6097574011 * m_ - 0.3413193965 * s_
    bl = -0.0041960863 * l_ - 0.7034186147 * m_ + 1.7076147010 * s_

    0.2126 * clip(r) + 0.7152 * clip(g) + 0.0722 * clip(bl)
  end

  defp clip(x), do: x |> max(0.0) |> min(1.0)
end
