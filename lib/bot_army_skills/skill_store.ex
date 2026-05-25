defmodule BotArmySkills.SkillStore do
  @moduledoc """
  Database access layer for skills and tenant actions.

  Each bot that opts into DB-driven skills has the `skills` and
  `tenant_actions` tables in its own database. The calling bot must
  pass its Repo module via the `:repo` option so queries hit the
  right database.

  Example:

      SkillStore.get_active_skill(tenant_id, "summarize", repo: BotArmyGtd.Repo)

  If no repo is provided, falls back to BotArmyRuntime.Ecto.Repo
  (for development/convenience only).
  """

  alias BotArmySkills.{TenantAction, SkillDefinition}

  @default_tenant_id BotArmyRuntime.Tenant.default_tenant_id()

  # --- Skills ---

  @doc "Get the active version of a skill by tenant and slug."
  @spec get_active_skill(String.t(), String.t(), keyword()) :: SkillDefinition.t() | nil
  def get_active_skill(tenant_id, slug, opts \\ []) do
    repo = Keyword.get(opts, :repo, BotArmyRuntime.Ecto.Repo)

    query = """
    SELECT id, tenant_id, name, slug, markdown_content, version, is_active
    FROM skills
    WHERE tenant_id = $1::uuid
      AND slug = $2
      AND is_active = true
    ORDER BY version DESC
    LIMIT 1
    """

    case repo_query(repo, query, [tenant_id, slug]) do
      {:ok, %Postgrex.Result{rows: [row]}} ->
        row_to_skill_definition(row)

      {:ok, %Postgrex.Result{rows: []}} ->
        nil

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Get all active skills for a tenant."
  @spec list_active_skills(String.t(), keyword()) :: [SkillDefinition.t()]
  def list_active_skills(tenant_id, opts \\ []) do
    repo = Keyword.get(opts, :repo, BotArmyRuntime.Ecto.Repo)

    query = """
    SELECT id, tenant_id, name, slug, markdown_content, version, is_active
    FROM skills
    WHERE tenant_id = $1::uuid
      AND is_active = true
    ORDER BY slug, version DESC
    """

    case repo_query(repo, query, [tenant_id]) do
      {:ok, %Postgrex.Result{rows: rows}} ->
        Enum.map(rows, &row_to_skill_definition/1)

      {:error, _reason} ->
        []
    end
  end

  @doc "Get a specific version of a skill."
  @spec get_skill_version(String.t(), String.t(), integer(), keyword()) ::
          SkillDefinition.t() | nil
  def get_skill_version(tenant_id, slug, version, opts \\ []) do
    repo = Keyword.get(opts, :repo, BotArmyRuntime.Ecto.Repo)

    query = """
    SELECT id, tenant_id, name, slug, markdown_content, version, is_active
    FROM skills
    WHERE tenant_id = $1::uuid
      AND slug = $2
      AND version = $3
    """

    case repo_query(repo, query, [tenant_id, slug, version]) do
      {:ok, %Postgrex.Result{rows: [row]}} ->
        row_to_skill_definition(row)

      {:ok, %Postgrex.Result{rows: []}} ->
        nil

      {:error, _reason} ->
        nil
    end
  end

  @doc """
  Create a new skill version.

  If a skill with the same (tenant_id, slug) exists, the version is incremented.
  The new version is created as active and all previous versions are deactivated.
  """
  @spec create_skill(String.t(), map(), keyword()) ::
          {:ok, SkillDefinition.t()} | {:error, term()}
  def create_skill(tenant_id, attrs, opts \\ []) do
    repo = Keyword.get(opts, :repo, BotArmyRuntime.Ecto.Repo)

    slug = Map.fetch!(attrs, :slug)
    name = Map.get(attrs, :name, slug)
    markdown_content = Map.fetch!(attrs, :markdown_content)

    # Get current max version
    next_version =
      case get_max_version(repo, tenant_id, slug) do
        nil -> 1
        v -> v + 1
      end

    query = """
    INSERT INTO skills (tenant_id, name, slug, markdown_content, version, is_active, inserted_at, updated_at)
    VALUES ($1::uuid, $2, $3, $4, $5, true, timezone('UTC', now()), timezone('UTC', now()))
    RETURNING id, tenant_id, name, slug, markdown_content, version, is_active
    """

    case repo_query(repo, query, [tenant_id, name, slug, markdown_content, next_version]) do
      {:ok, %Postgrex.Result{rows: [row]}} ->
        # Deactivate all other versions of this (tenant_id, slug)
        deactivate_other_versions(repo, tenant_id, slug, next_version)
        publish_cache_invalidation(tenant_id, slug)
        {:ok, row_to_skill_definition(row)}

      {:ok, %Postgrex.Result{rows: []}} ->
        {:error, "No rows returned from insert"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Activate a specific version, deactivating all other versions of that (tenant_id, slug)."
  @spec activate_version(String.t(), String.t(), integer(), keyword()) ::
          {:ok, SkillDefinition.t()} | {:error, term()}
  def activate_version(tenant_id, slug, version, opts \\ []) do
    repo = Keyword.get(opts, :repo, BotArmyRuntime.Ecto.Repo)

    # Deactivate all versions
    deactivate_query = """
    UPDATE skills SET is_active = false, updated_at = timezone('UTC', now())
    WHERE tenant_id = $1::uuid AND slug = $2
    """

    :ok = repo_query(repo, deactivate_query, [tenant_id, slug])

    # Activate the target version
    activate_query = """
    UPDATE skills SET is_active = true, updated_at = timezone('UTC', now())
    WHERE tenant_id = $1::uuid AND slug = $2 AND version = $3
    RETURNING id, tenant_id, name, slug, markdown_content, version, is_active
    """

    case repo_query(repo, activate_query, [tenant_id, slug, version]) do
      {:ok, %Postgrex.Result{rows: [row]}} ->
        publish_cache_invalidation(tenant_id, slug)
        {:ok, row_to_skill_definition(row)}

      {:ok, %Postgrex.Result{rows: []}} ->
        {:error, {:version_not_found, version}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Deactivate the current active version. Activates the previous version if one exists."
  @spec deactivate_current(String.t(), String.t(), keyword()) ::
          {:ok, SkillDefinition.t() | nil} | {:error, term()}
  def deactivate_current(tenant_id, slug, opts \\ []) do
    repo = Keyword.get(opts, :repo, BotArmyRuntime.Ecto.Repo)

    # Get current active version
    case get_active_skill(tenant_id, slug, opts) do
      nil ->
        {:ok, nil}

      current ->
        # Deactivate current
        deactivate_query = """
        UPDATE skills SET is_active = false, updated_at = timezone('UTC', now())
        WHERE tenant_id = $1::uuid AND slug = $2 AND version = $3
        """

        repo_query(repo, deactivate_query, [tenant_id, slug, current.version])

        # Try to activate previous version
        prev_query = """
        UPDATE skills SET is_active = true, updated_at = timezone('UTC', now())
        WHERE tenant_id = $1::uuid AND slug = $2 AND version = (
          SELECT MAX(version) FROM skills
          WHERE tenant_id = $1::uuid AND slug = $2 AND version < $3
        )
        RETURNING id, tenant_id, name, slug, markdown_content, version, is_active
        """

        case repo_query(repo, prev_query, [tenant_id, slug, current.version]) do
          {:ok, %Postgrex.Result{rows: [row]}} ->
            publish_cache_invalidation(tenant_id, slug)
            {:ok, row_to_skill_definition(row)}

          {:ok, %Postgrex.Result{rows: []}} ->
            publish_cache_invalidation(tenant_id, slug)
            {:ok, nil}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @doc "List version history for a skill."
  @spec list_versions(String.t(), String.t(), keyword()) :: [SkillDefinition.t()]
  def list_versions(tenant_id, slug, opts \\ []) do
    repo = Keyword.get(opts, :repo, BotArmyRuntime.Ecto.Repo)

    query = """
    SELECT id, tenant_id, name, slug, markdown_content, version, is_active
    FROM skills
    WHERE tenant_id = $1::uuid AND slug = $2
    ORDER BY version DESC
    """

    case repo_query(repo, query, [tenant_id, slug]) do
      {:ok, %Postgrex.Result{rows: rows}} ->
        Enum.map(rows, &row_to_skill_definition/1)

      {:error, _reason} ->
        []
    end
  end

  # --- Tenant Actions ---

  @doc "Get an action by tenant and slug."
  @spec get_action(String.t(), String.t(), keyword()) :: TenantAction.t() | nil
  def get_action(tenant_id, slug, opts \\ []) do
    repo = Keyword.get(opts, :repo, BotArmyRuntime.Ecto.Repo)

    query = """
    SELECT id, tenant_id, slug, type, config_json, is_active
    FROM tenant_actions
    WHERE tenant_id = $1::uuid AND slug = $2
    """

    case repo_query(repo, query, [tenant_id, slug]) do
      {:ok, %Postgrex.Result{rows: [row]}} ->
        row_to_tenant_action(row)

      {:ok, %Postgrex.Result{rows: []}} ->
        nil

      {:error, _reason} ->
        nil
    end
  end

  @doc "List all active actions for a tenant."
  @spec list_active_actions(String.t(), keyword()) :: [TenantAction.t()]
  def list_active_actions(tenant_id, opts \\ []) do
    repo = Keyword.get(opts, :repo, BotArmyRuntime.Ecto.Repo)

    query = """
    SELECT id, tenant_id, slug, type, config_json, is_active
    FROM tenant_actions
    WHERE tenant_id = $1::uuid AND is_active = true
    ORDER BY slug
    """

    case repo_query(repo, query, [tenant_id]) do
      {:ok, %Postgrex.Result{rows: rows}} ->
        Enum.map(rows, &row_to_tenant_action/1)

      {:error, _reason} ->
        []
    end
  end

  @doc "Create or update an action."
  @spec upsert_action(String.t(), map(), keyword()) ::
          {:ok, TenantAction.t()} | {:error, term()}
  def upsert_action(tenant_id, attrs, opts \\ []) do
    repo = Keyword.get(opts, :repo, BotArmyRuntime.Ecto.Repo)

    slug = Map.fetch!(attrs, :slug)
    type = Map.fetch!(attrs, :type)
    config_json = Map.get(attrs, :config_json, %{})

    query = """
    INSERT INTO tenant_actions (tenant_id, slug, type, config_json, is_active, inserted_at, updated_at)
    VALUES ($1::uuid, $2, $3, $4::jsonb, true, timezone('UTC', now()), timezone('UTC', now()))
    ON CONFLICT (tenant_id, slug)
    DO UPDATE SET
      type = $3,
      config_json = $4::jsonb,
      is_active = true,
      updated_at = timezone('UTC', now())
    RETURNING id, tenant_id, slug, type, config_json, is_active
    """

    case repo_query(repo, query, [tenant_id, slug, type, Jason.encode!(config_json)]) do
      {:ok, %Postgrex.Result{rows: [row]}} ->
        {:ok, row_to_tenant_action(row)}

      {:ok, %Postgrex.Result{rows: []}} ->
        {:error, "No rows returned from upsert"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # --- Seeding ---

  @doc "Seed canonical skills from the default tenant for a new tenant."
  @spec seed_canonical_skills(String.t(), keyword()) :: [SkillDefinition.t()]
  def seed_canonical_skills(tenant_id, opts \\ []) do
    repo = Keyword.get(opts, :repo, BotArmyRuntime.Ecto.Repo)

    query = """
    INSERT INTO skills (tenant_id, name, slug, markdown_content, version, is_active, inserted_at, updated_at)
    SELECT $1::uuid, name, slug, markdown_content, 1, true, timezone('UTC', now()), timezone('UTC', now())
    FROM skills
    WHERE tenant_id = $2::uuid AND is_active = true
    ON CONFLICT (tenant_id, slug, version) DO NOTHING
    """

    repo_query(repo, query, [tenant_id, @default_tenant_id])
    list_active_skills(tenant_id, opts)
  end

  @doc "Seed canonical actions from the default tenant for a new tenant."
  @spec seed_canonical_actions(String.t(), keyword()) :: [TenantAction.t()]
  def seed_canonical_actions(tenant_id, opts \\ []) do
    repo = Keyword.get(opts, :repo, BotArmyRuntime.Ecto.Repo)

    query = """
    INSERT INTO tenant_actions (tenant_id, slug, type, config_json, is_active, inserted_at, updated_at)
    SELECT $1::uuid, slug, type, config_json, true, timezone('UTC', now()), timezone('UTC', now())
    FROM tenant_actions
    WHERE tenant_id = $2::uuid AND is_active = true
    ON CONFLICT (tenant_id, slug) DO NOTHING
    """

    repo_query(repo, query, [tenant_id, @default_tenant_id])
    list_active_actions(tenant_id, opts)
  end

  # --- Private helpers ---

  defp get_max_version(repo, tenant_id, slug) do
    query = """
    SELECT MAX(version) FROM skills
    WHERE tenant_id = $1::uuid AND slug = $2
    """

    case repo_query(repo, query, [tenant_id, slug]) do
      {:ok, %Postgrex.Result{rows: [[nil]]}} -> nil
      {:ok, %Postgrex.Result{rows: [[max]]}} -> max
      {:error, _reason} -> nil
    end
  end

  defp deactivate_other_versions(repo, tenant_id, slug, current_version) do
    query = """
    UPDATE skills SET is_active = false, updated_at = timezone('UTC', now())
    WHERE tenant_id = $1::uuid AND slug = $2 AND version != $3
    """

    repo_query(repo, query, [tenant_id, slug, current_version])
    :ok
  end

  defp row_to_skill_definition([id, tenant_id, name, slug, markdown_content, version, is_active]) do
    row_map = %{
      id: id,
      tenant_id: tenant_id,
      name: name,
      slug: slug,
      markdown_content: markdown_content,
      version: version,
      is_active: is_active
    }

    SkillDefinition.from_db_row(row_map)
  end

  defp row_to_tenant_action([id, tenant_id, slug, type, config_json, is_active]) do
    %TenantAction{
      id: id,
      tenant_id: tenant_id,
      slug: slug,
      type: type,
      config_json: config_json,
      is_active: is_active
    }
  end

  defp publish_cache_invalidation(tenant_id, slug) do
    BotArmyCore.NATS.publish("bot.army.skills.cache.invalidate", %{
      "tenant_id" => tenant_id,
      "slug" => slug
    })
  rescue
    _ -> :ok
  catch
    :exit, _ -> :ok
  end

  defp repo_query(repo, query, params) do
    repo.query(query, Enum.map(params, &normalize_param/1))
  end

  defp normalize_param(param) when is_binary(param) do
    case Ecto.UUID.dump(param) do
      {:ok, uuid_bin} -> uuid_bin
      :error -> param
    end
  end

  defp normalize_param(param), do: param
end
