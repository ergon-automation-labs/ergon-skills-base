defmodule BotArmySkills.Seeder do
  @moduledoc """
  Seeds canonical skills and actions for tenants.

  Canonical skills are stored as markdown files in `priv/canonical_skills/`
  and are copied into the database with the default tenant ID. When a new
  tenant is provisioned, these skills are cloned for that tenant.

  ## Mix task

      mix skills.seed

  Loads canonical skills from `priv/canonical_skills/` into the default tenant.
  """

  require Logger

  alias BotArmySkills.SkillStore

  @default_tenant_id BotArmyRuntime.Tenant.default_tenant_id()

  @doc "Seed canonical skills for the default tenant from priv/canonical_skills/"
  @spec seed_default_tenant!(keyword()) :: [:ok | {:error, term()}]
  def seed_default_tenant!(opts \\ []) do
    canonical_dir = canonical_skills_dir()
    seed_skills_from_directory(@default_tenant_id, canonical_dir, opts)
  end

  @doc "Provision a new tenant by cloning default tenant's skills and actions."
  @spec provision_tenant(String.t(), keyword()) :: {:ok, [map()]}
  def provision_tenant(tenant_id, opts \\ []) do
    skills = SkillStore.seed_canonical_skills(tenant_id, opts)
    actions = SkillStore.seed_canonical_actions(tenant_id, opts)
    {:ok, %{skills: skills, actions: actions}}
  end

  @doc "Seed skills from a directory of .md files for a given tenant."
  @spec seed_skills_from_directory(String.t(), String.t(), keyword()) ::
          [:ok | {:error, term()}]
  def seed_skills_from_directory(tenant_id, dir, opts \\ []) do
    case File.ls(dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".md"))
        |> Enum.map(fn file ->
          path = Path.join(dir, file)
          seed_skill_from_file(tenant_id, path, opts)
        end)

      {:error, reason} ->
        Logger.warning("Canonical skills directory not found: #{dir} (#{reason})")
        []
    end
  end

  @doc "Seed a single skill from a markdown file."
  @spec seed_skill_from_file(String.t(), String.t(), keyword()) ::
          :ok | {:error, term()}
  def seed_skill_from_file(tenant_id, path, opts \\ []) do
    case File.read(path) do
      {:ok, content} ->
        {frontmatter, _body} = parse_frontmatter(content)

        slug =
          Map.get(frontmatter, :slug, Map.get(frontmatter, :name, Path.basename(path, ".md")))

        name = Map.get(frontmatter, :name, slug)

        case SkillStore.create_skill(
               tenant_id,
               %{
                 slug: to_string(slug),
                 name: to_string(name),
                 markdown_content: content
               },
               opts
             ) do
          {:ok, _skill} ->
            Logger.info("Seeded skill: #{slug}")
            :ok

          {:error, reason} ->
            Logger.warning("Failed to seed skill #{slug}: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, reason} ->
        Logger.warning("Failed to read skill file #{path}: #{reason}")
        {:error, reason}
    end
  end

  defp canonical_skills_dir do
    :code.priv_dir(:bot_army_skills)
    |> to_string()
    |> Path.join("canonical_skills")
  rescue
    _ -> Path.join([:code.root_dir(), "lib", "bot_army_skills", "priv", "canonical_skills"])
  end

  defp parse_frontmatter(content) do
    case String.split(content, "---", parts: 3) do
      ["", frontmatter, body] ->
        attrs = parse_frontmatter_text(frontmatter)
        {attrs, body}

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
  defp parse_frontmatter_value(:slug, value), do: value
  defp parse_frontmatter_value(:triggers, value), do: [value]
  defp parse_frontmatter_value(:llm_hint, value), do: String.to_atom(value)
  defp parse_frontmatter_value(_key, value), do: value
end
