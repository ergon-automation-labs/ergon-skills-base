defmodule BotArmySkills.Handlers.ContentHandler do
  @moduledoc """
  Read-only skill catalog over NATS (markdown from DB cache, no SkillRunner).
  """

  @behaviour BotArmySkills.Handler

  alias BotArmySkills.SkillCache

  @default_tenant_id "00000000-0000-0000-0000-000000000001"

  @impl BotArmySkills.Handler
  def subjects do
    [
      %{
        subject: "bot.army.skills.content.list",
        type: :request_reply,
        description: "List active skills for tenant (markdown catalog, no LLM)"
      },
      %{
        subject: "bot.army.skills.content.get",
        type: :request_reply,
        description: "Fetch one skill markdown by slug (no LLM)"
      }
    ]
  end

  @impl BotArmySkills.Handler
  def handle_message("bot.army.skills.content.list", query), do: handle_list(query)
  def handle_message("bot.army.skills.content.get", query), do: handle_get(query)

  def handle_list(query) when is_map(query) do
    tenant_id = tenant_id_from(query)

    skills =
      tenant_id
      |> SkillCache.list_skills()
      |> Enum.map(&summarize/1)
      |> Enum.sort_by(& &1["slug"])

    %{"tenant_id" => tenant_id, "skills" => skills}
  end

  def handle_get(query) when is_map(query) do
    tenant_id = tenant_id_from(query)
    slug = Map.get(query, "slug") || Map.get(query, "skill")

    case slug do
      s when is_binary(s) and s != "" ->
        case SkillCache.get_skill(tenant_id, s) do
          nil ->
            %{"error" => "skill_not_found", "slug" => s, "tenant_id" => tenant_id}

          skill ->
            %{
              "tenant_id" => tenant_id,
              "slug" => skill.slug,
              "name" => Atom.to_string(skill.name),
              "description" => skill.description,
              "version" => skill.version,
              "markdown" => skill.markdown_content
            }
        end

      _ ->
        %{"error" => "missing_slug"}
    end
  end

  defp tenant_id_from(query) do
    case Map.get(query, "tenant_id") do
      id when is_binary(id) and id != "" -> id
      _ -> @default_tenant_id
    end
  end

  defp summarize(skill) do
    %{
      "slug" => skill.slug,
      "name" => Atom.to_string(skill.name),
      "description" => skill.description,
      "version" => skill.version
    }
  end
end
