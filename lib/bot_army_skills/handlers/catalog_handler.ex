defmodule BotArmySkills.Handlers.CatalogHandler do
  @moduledoc """
  Canonical skill catalog (git `priv/canonical_skills`) vs tenant-installed skills.
  """

  @behaviour BotArmySkills.Handler

  alias BotArmySkills.SkillCache

  @default_tenant_id "00000000-0000-0000-0000-000000000001"
  @canonical_dir "priv/canonical_skills"

  @impl BotArmySkills.Handler
  def subjects do
    [
      %{
        subject: "bot.army.skills.catalog.canonical",
        type: :request_reply,
        description: "List canonical skills from priv/canonical_skills (install catalog)"
      },
      %{
        subject: "bot.army.skills.catalog.suggest",
        type: :request_reply,
        description: "Suggest canonical skills not installed for tenant"
      }
    ]
  end

  @impl BotArmySkills.Handler
  def handle_message("bot.army.skills.catalog.canonical", query), do: handle_canonical_list(query)
  def handle_message("bot.army.skills.catalog.suggest", query), do: handle_suggest(query)

  def handle_canonical_list(_query) do
    %{"skills" => list_canonical_entries()}
  end

  def handle_suggest(query) when is_map(query) do
    tenant_id = tenant_id_from(query)
    query_text = Map.get(query, "query") || Map.get(query, "text") || ""

    installed =
      tenant_id
      |> SkillCache.list_skills()
      |> Enum.map(& &1.slug)
      |> MapSet.new()

    canonical = list_canonical_entries()

    missing =
      canonical
      |> Enum.reject(fn entry -> MapSet.member?(installed, entry["slug"]) end)
      |> maybe_rank_by_query(query_text)

    %{
      "tenant_id" => tenant_id,
      "installed_count" => MapSet.size(installed),
      "suggestions" => Enum.take(missing, suggest_limit(query))
    }
  end

  defp suggest_limit(query) do
    case Map.get(query, "limit") do
      n when is_integer(n) and n > 0 ->
        min(n, 25)

      n when is_binary(n) ->
        case Integer.parse(n) do
          {i, _} when i > 0 -> min(i, 25)
          _ -> 8
        end

      _ ->
        8
    end
  end

  defp maybe_rank_by_query(entries, ""), do: entries

  defp maybe_rank_by_query(entries, query_text) do
    tokens =
      query_text
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9\s]/, " ")
      |> String.split(~r/\s+/, trim: true)
      |> Enum.reject(&(String.length(&1) < 3))

    if tokens == [] do
      entries
    else
      entries
      |> Enum.map(fn entry ->
        hay =
          [
            entry["slug"],
            entry["name"],
            entry["description"],
            Enum.join(entry["tags"] || [], " ")
          ]
          |> Enum.join(" ")
          |> String.downcase()

        score = Enum.count(tokens, &String.contains?(hay, &1))
        {score, entry}
      end)
      |> Enum.sort_by(fn {score, entry} -> {-score, entry["slug"]} end)
      |> Enum.map(fn {_score, entry} -> entry end)
    end
  end

  defp list_canonical_entries do
    root = Application.app_dir(:bot_army_skills, @canonical_dir)

    case File.ls(root) do
      {:ok, names} ->
        names
        |> Enum.filter(&String.ends_with?(&1, ".md"))
        |> Enum.reject(&(&1 == "README.md"))
        |> Enum.map(fn name ->
          path = Path.join(root, name)
          slug = Path.rootname(name)

          case File.read(path) do
            {:ok, content} -> entry_from_markdown(slug, content)
            {:error, _} -> %{"slug" => slug, "name" => slug, "description" => nil, "tags" => []}
          end
        end)
        |> Enum.sort_by(& &1["slug"])

      {:error, _} ->
        []
    end
  end

  defp entry_from_markdown(slug, content) do
    {fm, _body} = split_frontmatter(content)

    %{
      "slug" => slug,
      "name" => fm["name"] || slug,
      "description" => fm["description"],
      "tags" => fm["tags"] || [],
      "llm_hint" => fm["llm_hint"] || "none",
      "install_hint" => fm["install_hint"] || "Run skills_bot migrations / seed for tenant"
    }
  end

  defp split_frontmatter(content) do
    case String.split(content, "---", parts: 3) do
      ["", frontmatter, body] ->
        {parse_frontmatter_yaml(frontmatter), String.trim(body)}

      _ ->
        {%{}, content}
    end
  end

  defp parse_frontmatter_yaml(text) do
    text
    |> String.split("\n")
    |> Enum.reduce(%{}, fn line, acc ->
      case String.split(line, ":", parts: 2) do
        [key, value] ->
          k = String.trim(key)
          v = String.trim(value)

          parsed =
            if k == "tags" and String.starts_with?(v, "[") do
              v
              |> String.trim_leading("[")
              |> String.trim_trailing("]")
              |> String.split(",")
              |> Enum.map(&String.trim/1)
              |> Enum.map(&String.trim(&1, "\""))
              |> Enum.reject(&(&1 == ""))
            else
              v
            end

          Map.put(acc, k, parsed)

        _ ->
          acc
      end
    end)
  end

  defp tenant_id_from(query) do
    case Map.get(query, "tenant_id") do
      id when is_binary(id) and id != "" -> id
      _ -> @default_tenant_id
    end
  end
end
