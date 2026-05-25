defmodule BotArmySkills.Handlers.BionicReadingHandler do
  @moduledoc """
  Algorithmic bionic reading transformation — bolds the first portion of each word
  to guide the eye and improve reading speed. No LLM required.

  Request: %{"text" => "Hello world", "format" => "markdown"}
  Response: %{"ok" => true, "text" => "**Hel**lo **wor**ld", "stats" => %{...}}
  """

  @behaviour BotArmySkills.Handler

  @default_ratio 0.4
  @default_format "markdown"

  def handle_transform(query) when is_map(query) do
    text = Map.get(query, "text", "")
    env_ratio = env_default_ratio()
    ratio = parse_ratio(Map.get(query, "ratio", env_ratio))
    format = parse_format(Map.get(query, "format", @default_format))

    if text == "" do
      %{"ok" => true, "text" => "", "stats" => %{"words" => 0, "bolded" => 0}}
    else
      {transformed, stats} = transform(text, ratio, format)
      %{"ok" => true, "text" => transformed, "stats" => stats}
    end
  end

  defp transform(text, ratio, format) do
    words = split_words(text)
    bold_fn = bold_function(format)

    {transformed_words, bolded_count} =
      Enum.reduce(words, {[], 0}, fn {word, before_text, after_text}, {acc, count} ->
        bold_len = bold_length(word, ratio)

        {bolded_word, new_count} =
          if String.length(word) > 1 do
            {bold_part, rest} = String.split_at(word, bold_len)
            {bold_fn.(bold_part) <> rest, count + 1}
          else
            {word, count}
          end

        {acc ++ [before_text, bolded_word, after_text], new_count}
      end)

    transformed = IO.iodata_to_binary(transformed_words)
    stats = %{"words" => length(words), "bolded" => bolded_count, "ratio" => ratio}

    {transformed, stats}
  end

  defp split_words(text) do
    Regex.scan(~r/([^\w]*)([\w]+)([^\w]*)/u, text, return: :binary)
    |> Enum.map(fn
      [full] -> {full, "", ""}
      [_, before, word, after_t] -> {word, before, after_t}
    end)
  end

  defp bold_length(word, ratio) do
    len = String.length(word)
    max(1, round(len * ratio))
  end

  defp bold_function("html"), do: &html_bold/1
  defp bold_function(_), do: &markdown_bold/1

  defp markdown_bold(part), do: "**#{part}**"
  defp html_bold(part), do: "<b>#{part}</b>"

  defp parse_ratio(r) when is_float(r) and r > 0 and r < 1, do: r
  defp parse_ratio(r) when is_integer(r), do: r / 100.0

  defp parse_ratio(r) when is_binary(r) do
    case Float.parse(r) do
      {f, _} when f > 0 and f < 1 -> f
      {f, _} -> f / 100.0
      :error -> @default_ratio
    end
  end

  defp parse_ratio(_), do: @default_ratio

  @impl BotArmySkills.Handler
  def subjects do
    [
      %{
        subject: "bot.army.skills.bionic_reading.transform",
        type: :request_reply,
        description: "Transform text with bionic reading formatting (algorithmic, no LLM)"
      }
    ]
  end

  @impl BotArmySkills.Handler
  def handle_message("bot.army.skills.bionic_reading.transform", query),
    do: handle_transform(query)

  defp env_default_ratio do
    case System.get_env("BIONIC_READING_RATIO") do
      nil -> @default_ratio
      val -> parse_ratio(val)
    end
  end

  defp parse_format("html"), do: "html"
  defp parse_format(_), do: @default_format
end
