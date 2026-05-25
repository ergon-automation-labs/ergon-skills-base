defmodule BotArmySkills.SkillCache do
  @moduledoc """
  ETS-backed cache for active skills and actions, scoped per tenant.

  Each bot has its own database, so the cache needs to know which
  Repo to use per tenant. The repo is set when a tenant is first
  loaded and passed through to SkillStore on all DB calls.

  Provides fast lookups without hitting the database on every skill execution.
  Supports two invalidation strategies:

  1. NATS event notification (push) — subscribes to `bot.army.skills.cache.invalidate`
  2. Time-based polling (pull, fallback) — refreshes every 5 minutes

  Cache keys: `{tenant_id, :skill, slug}` and `{tenant_id, :action, slug}`.
  """

  use GenServer

  alias BotArmySkills.{SkillStore, SkillDefinition}

  @table :bot_army_skills_cache
  @poll_interval :timer.minutes(5)
  @miss_ttl :timer.seconds(30)
  @missing_skill :__missing_skill__

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Get an active skill from cache, loading from DB on miss."
  @spec get_skill(String.t(), String.t(), keyword()) :: SkillDefinition.t() | nil
  def get_skill(tenant_id, slug, opts \\ []) do
    repo = Keyword.get(opts, :repo, BotArmyRuntime.Ecto.Repo)

    case :ets.lookup(@table, {tenant_id, :skill, slug}) do
      [{_key, @missing_skill, _expires_at}] ->
        nil

      [{_key, skill, _expires_at}] ->
        skill

      [] ->
        GenServer.call(__MODULE__, {:load_skill, tenant_id, slug, repo})
    end
  end

  @doc "Get all active skills for a tenant from cache."
  @spec list_skills(String.t(), keyword()) :: [SkillDefinition.t()]
  def list_skills(tenant_id, opts \\ []) do
    repo = Keyword.get(opts, :repo, BotArmyRuntime.Ecto.Repo)

    case :ets.lookup(@table, {:tenant_loaded, tenant_id}) do
      [{_key, true, _expires_at}] ->
        :ets.match_object(@table, {{tenant_id, :skill, :_}, :_, :_})
        |> Enum.map(fn {_key, skill, _expires_at} -> skill end)

      [] ->
        GenServer.call(__MODULE__, {:load_tenant, tenant_id, repo})
    end
  end

  @doc "Get an action from cache, loading from DB on miss."
  @spec get_action(String.t(), String.t(), keyword()) :: BotArmySkills.TenantAction.t() | nil
  def get_action(tenant_id, slug, opts \\ []) do
    repo = Keyword.get(opts, :repo, BotArmyRuntime.Ecto.Repo)

    case :ets.lookup(@table, {tenant_id, :action, slug}) do
      [{_key, action, _expires_at}] ->
        action

      [] ->
        GenServer.call(__MODULE__, {:load_action, tenant_id, slug, repo})
    end
  end

  @doc "Invalidate cache for a specific skill or all skills for a tenant."
  @spec invalidate(String.t(), String.t() | nil) :: :ok
  def invalidate(tenant_id, slug \\ nil) do
    GenServer.cast(__MODULE__, {:invalidate, tenant_id, slug})
  end

  @doc "Force refresh all cached data for a tenant."
  @spec refresh(String.t(), keyword()) :: :ok
  def refresh(tenant_id, opts \\ []) do
    repo = Keyword.get(opts, :repo, BotArmyRuntime.Ecto.Repo)
    GenServer.cast(__MODULE__, {:refresh, tenant_id, repo})
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    :ets.new(@table, [:set, :named_table, :public, {:read_concurrency, true}])

    try do
      BotArmyCore.NATS.subscribe("bot.army.skills.cache.invalidate")
    rescue
      _ -> :ok
    end

    schedule_poll()
    {:ok, %{tenants_loaded: MapSet.new(), tenant_repos: %{}}}
  end

  @impl true
  def handle_call({:load_skill, tenant_id, slug, repo}, _from, state) do
    case SkillStore.get_active_skill(tenant_id, slug, repo: repo) do
      nil ->
        # Negative cache misses briefly to avoid repeated DB hits for unknown slugs.
        expires_at = System.monotonic_time(:millisecond) + @miss_ttl
        :ets.insert(@table, {{tenant_id, :skill, slug}, @missing_skill, expires_at})
        {:reply, nil, state}

      skill ->
        expires_at = System.monotonic_time(:millisecond) + @poll_interval
        :ets.insert(@table, {{tenant_id, :skill, slug}, skill, expires_at})
        state = store_tenant_repo(state, tenant_id, repo)
        {:reply, skill, state}
    end
  end

  @impl true
  def handle_call({:load_tenant, tenant_id, repo}, _from, state) do
    skills = SkillStore.list_active_skills(tenant_id, repo: repo)
    expires_at = System.monotonic_time(:millisecond) + @poll_interval

    Enum.each(skills, fn skill ->
      :ets.insert(@table, {{tenant_id, :skill, skill.slug}, skill, expires_at})
    end)

    :ets.insert(@table, {{:tenant_loaded, tenant_id}, true, expires_at})
    state = store_tenant_repo(state, tenant_id, repo)
    {:reply, skills, %{state | tenants_loaded: MapSet.put(state.tenants_loaded, tenant_id)}}
  end

  @impl true
  def handle_call({:load_action, tenant_id, slug, repo}, _from, state) do
    case SkillStore.get_action(tenant_id, slug, repo: repo) do
      nil ->
        {:reply, nil, state}

      action ->
        expires_at = System.monotonic_time(:millisecond) + @poll_interval
        :ets.insert(@table, {{tenant_id, :action, slug}, action, expires_at})
        state = store_tenant_repo(state, tenant_id, repo)
        {:reply, action, state}
    end
  end

  @impl true
  def handle_cast({:invalidate, tenant_id, nil}, state) do
    :ets.match_delete(@table, {{tenant_id, :_, :_}, :_, :_})
    :ets.delete(@table, {:tenant_loaded, tenant_id})

    {:noreply,
     %{
       state
       | tenants_loaded: MapSet.delete(state.tenants_loaded, tenant_id),
         tenant_repos: Map.delete(state.tenant_repos, tenant_id)
     }}
  end

  @impl true
  def handle_cast({:invalidate, tenant_id, slug}, state) do
    :ets.delete(@table, {tenant_id, :skill, slug})
    :ets.delete(@table, {:tenant_loaded, tenant_id})
    {:noreply, %{state | tenants_loaded: MapSet.delete(state.tenants_loaded, tenant_id)}}
  end

  @impl true
  def handle_cast({:refresh, tenant_id, repo}, state) do
    :ets.match_delete(@table, {{tenant_id, :_, :_}, :_, :_})
    :ets.delete(@table, {:tenant_loaded, tenant_id})

    skills = SkillStore.list_active_skills(tenant_id, repo: repo)
    expires_at = System.monotonic_time(:millisecond) + @poll_interval

    Enum.each(skills, fn skill ->
      :ets.insert(@table, {{tenant_id, :skill, skill.slug}, skill, expires_at})
    end)

    :ets.insert(@table, {{:tenant_loaded, tenant_id}, true, expires_at})

    {:noreply,
     %{
       state
       | tenants_loaded: MapSet.put(state.tenants_loaded, tenant_id),
         tenant_repos: Map.put(state.tenant_repos, tenant_id, repo)
     }}
  end

  @impl true
  def handle_info(:poll, state) do
    Enum.each(state.tenants_loaded, fn tenant_id ->
      repo = Map.get(state.tenant_repos, tenant_id, BotArmyRuntime.Ecto.Repo)
      skills = SkillStore.list_active_skills(tenant_id, repo: repo)
      expires_at = System.monotonic_time(:millisecond) + @poll_interval

      Enum.each(skills, fn skill ->
        :ets.insert(@table, {{tenant_id, :skill, skill.slug}, skill, expires_at})
      end)

      :ets.insert(@table, {{:tenant_loaded, tenant_id}, true, expires_at})
    end)

    schedule_poll()
    {:noreply, state}
  end

  @impl true
  def handle_info({:msg, %{topic: "bot.army.skills.cache.invalidate", body: body}}, state) do
    case Jason.decode(body) do
      {:ok, payload} ->
        tenant_id = Map.get(payload, "tenant_id")
        slug = Map.get(payload, "slug")
        invalidate(tenant_id, slug)

      {:error, _} ->
        :ok
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  defp store_tenant_repo(state, tenant_id, repo) do
    %{state | tenant_repos: Map.put(state.tenant_repos, tenant_id, repo)}
  end

  defp schedule_poll do
    Process.send_after(self(), :poll, @poll_interval)
  end
end
