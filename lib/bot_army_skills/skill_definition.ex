defmodule BotArmySkills.SkillDefinition do
  @moduledoc """
  Runtime skill definition loaded from the database.

  Contains all the metadata needed to execute a markdown skill:
  template content, NATS triggers, LLM hint, and tenant scope.
  """

  @enforce_keys [:name, :slug, :tenant_id, :markdown_content, :version]
  defstruct [
    :name,
    :slug,
    :tenant_id,
    :markdown_content,
    :version,
    :description,
    :triggers,
    :llm_hint,
    :is_active,
    :db_id
  ]

  @type llm_hint :: :fast | :quality | :research | :none

  @type t :: %__MODULE__{
          name: atom(),
          slug: String.t(),
          tenant_id: String.t(),
          markdown_content: String.t(),
          version: integer(),
          description: String.t() | nil,
          triggers: [String.t()],
          llm_hint: llm_hint(),
          is_active: boolean(),
          db_id: String.t() | nil
        }

  @doc """
  Parse a Skill database row into a SkillDefinition struct.

  Extracts triggers and llm_hint from the markdown frontmatter.
  """
  @spec from_db_row(map()) :: t()
  def from_db_row(row) when is_map(row) do
    {frontmatter, body} =
      parse_frontmatter(row[:markdown_content] || row["markdown_content"] || "")

    %__MODULE__{
      name: frontmatter[:name] || String.to_atom(row[:slug] || row["slug"] || "unknown"),
      slug: row[:slug] || row["slug"],
      tenant_id: row[:tenant_id] || row["tenant_id"],
      markdown_content: body,
      version: row[:version] || row["version"] || 1,
      description: frontmatter[:description],
      triggers: frontmatter[:triggers] || [],
      llm_hint: frontmatter[:llm_hint] || :none,
      is_active: row[:is_active] || row["is_active"] || true,
      db_id: row[:id] || row["id"]
    }
  end

  defp parse_frontmatter(content) do
    case String.split(content, "---", parts: 3) do
      ["", frontmatter, body] ->
        attrs = parse_frontmatter_text(frontmatter)
        {attrs, String.trim(body)}

      _ ->
        {%{}, content}
    end
  end

  defp parse_frontmatter_text(text) do
    text
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.reduce(%{}, fn line, acc ->
      case String.split(line, ":", parts: 2) do
        [key, value] ->
          key_atom = String.trim(key) |> String.to_atom()
          value_str = String.trim(value)
          Map.put(acc, key_atom, parse_frontmatter_value(key_atom, value_str))

        _ ->
          acc
      end
    end)
  end

  defp parse_frontmatter_value(:name, value), do: String.to_atom(value)
  defp parse_frontmatter_value(:llm_hint, value), do: String.to_atom(value)
  defp parse_frontmatter_value(:triggers, value), do: [value]
  defp parse_frontmatter_value(_key, value), do: value

  # BotArmy.Skill-compatible callback wrappers.
  # These let SkillDefinition "quack like" a Skill without implementing the behaviour,
  # since the struct is not a module. GenBot dispatches via tagged tuples instead.

  @doc "Returns the skill's atom name (Skill-compatible wrapper)."
  def name(%__MODULE__{name: name}), do: name

  @doc "Returns the skill's NATS trigger subjects (Skill-compatible wrapper)."
  def nats_triggers(%__MODULE__{triggers: triggers}), do: triggers || []

  @doc "DB skills don't validate input — always returns :ok (Skill-compatible wrapper)."
  def validate(%__MODULE__{}), do: :ok

  @doc "Delegates to SkillRunner.execute (Skill-compatible wrapper)."
  def execute(%__MODULE__{} = skill, input, ctx) do
    BotArmySkills.SkillRunner.execute(skill, input, ctx, [])
  end
end
