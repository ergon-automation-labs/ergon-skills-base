defmodule BotArmySkills.BridgeRequestValidator do
  @moduledoc """
  Validates bridge request payload shapes before executing NATS request/reply actions.
  """

  @valid_priorities ["low", "normal", "high", "urgent"]
  @valid_contexts ["inbox", "next", "someday", "reference", "waiting"]
  @valid_presentations ["plain", "chronicle"]

  @spec validate(String.t(), map()) :: :ok | {:error, term()}
  def validate(subject, payload) when is_binary(subject) and is_map(payload) do
    case subject do
      "bridge.task.list" -> validate_task_list(payload)
      "bridge.task.create" -> validate_task_create(payload)
      "bridge.task.get" -> require_string(payload, "task_id")
      "bridge.task.update" -> require_string(payload, "task_id")
      "bridge.task.complete" -> require_string(payload, "task_id")
      "bridge.project.list" -> validate_empty(payload)
      "bridge.project.create" -> validate_project_create(payload)
      "bridge.goal.list" -> validate_empty(payload)
      "bridge.internal_docs.query" -> validate_internal_docs_query(payload)
      "bridge.synapse.awareness" -> validate_synapse_awareness(payload)
      "bridge.system.fact" -> validate_empty(payload)
      "bridge.chronicle.daily.brief" -> validate_chronicle_daily_brief(payload)
      "bridge.youtube.transcript.get" -> validate_youtube_transcript_get(payload)
      "bridge.random.roll" -> validate_random_roll(payload)
      "bridge.time.ntp.query" -> validate_time_ntp_query(payload)
      "bridge.army.opinion.elicit" -> validate_opinion_elicit(payload)
      "bridge.army.opinion.collect" -> validate_opinion_collect(payload)
      "bridge.gtd.poll.start" -> validate_gtd_poll_start(payload)
      "bridge.gtd.poll.vote.submit" -> validate_gtd_poll_vote_submit(payload)
      "bridge.gtd.poll.close" -> validate_gtd_poll_id_only(payload)
      "bridge.gtd.poll.get" -> validate_gtd_poll_id_only(payload)
      _ -> :ok
    end
  end

  def validate(_subject, _payload), do: {:error, :invalid_payload}

  defp validate_task_list(payload) do
    with :ok <- optional_integer(payload, "limit", 1, 500),
         :ok <- optional_integer(payload, "offset", 0, 1_000_000),
         :ok <- optional_string(payload, "project_id"),
         :ok <- optional_string(payload, "goal_id") do
      :ok
    end
  end

  defp validate_task_create(payload) do
    with :ok <- require_string(payload, "title"),
         :ok <- optional_string(payload, "description"),
         :ok <- optional_enum(payload, "priority", @valid_priorities),
         :ok <- optional_enum(payload, "context", @valid_contexts),
         :ok <- optional_string_list(payload, "labels"),
         :ok <- optional_string(payload, "project_id"),
         :ok <- optional_string(payload, "goal_id"),
         :ok <- optional_boolean(payload, "decompose"),
         :ok <- optional_string(payload, "decompose_model"),
         :ok <- optional_string(payload, "decompose_chain_id") do
      :ok
    end
  end

  defp validate_project_create(payload) do
    with :ok <- require_string(payload, "name"),
         :ok <- optional_string(payload, "description") do
      :ok
    end
  end

  defp validate_internal_docs_query(payload) do
    with :ok <- require_string(payload, "query"),
         :ok <- optional_integer(payload, "limit", 1, 50) do
      :ok
    end
  end

  defp validate_synapse_awareness(payload) do
    optional_integer(payload, "task_limit", 1, 50)
  end

  defp validate_chronicle_daily_brief(payload) do
    with :ok <- optional_enum(payload, "presentation", @valid_presentations),
         :ok <- optional_string(payload, "choice"),
         :ok <- optional_integer(payload, "task_limit", 1, 500),
         :ok <- optional_boolean(payload, "live") do
      :ok
    end
  end

  defp validate_youtube_transcript_get(payload) do
    with :ok <- require_string(payload, "youtube_url"),
         :ok <- optional_string(payload, "language"),
         :ok <- optional_boolean(payload, "include_timestamps"),
         :ok <- optional_boolean(payload, "include_video_metadata"),
         :ok <- optional_integer(payload, "max_chars", 1, 200_000),
         :ok <- optional_boolean(payload, "persist") do
      :ok
    end
  end

  defp validate_random_roll(payload) do
    with :ok <- require_string(payload, "notation"),
         :ok <- notation_length_ok(payload),
         :ok <- optional_string(payload, "seed"),
         :ok <- optional_string(payload, "purpose") do
      :ok
    end
  end

  defp notation_length_ok(payload) do
    case Map.get(payload, "notation") do
      s when is_binary(s) ->
        len = String.length(s)

        cond do
          len < 2 -> {:error, {:notation_too_short, len}}
          len > 64 -> {:error, {:notation_too_long, len}}
          true -> :ok
        end

      _ ->
        :ok
    end
  end

  defp validate_time_ntp_query(payload) do
    with :ok <- require_string(payload, "timezone"),
         :ok <- require_string(payload, "ntp_server") do
      :ok
    end
  end

  defp validate_opinion_elicit(payload) do
    with :ok <- require_schema_version_1_0(payload),
         :ok <- require_string(payload, "question"),
         :ok <- optional_string(payload, "correlation_id"),
         :ok <- optional_string_list(payload, "options") do
      :ok
    end
  end

  defp validate_opinion_collect(payload) do
    with :ok <- require_schema_version_1_0(payload),
         :ok <- require_string(payload, "question"),
         :ok <- optional_string(payload, "correlation_id"),
         :ok <- optional_string_list(payload, "options"),
         :ok <- optional_string_list(payload, "human_responses"),
         :ok <- optional_integer(payload, "timeout_ms_per_voter", 200, 120_000) do
      :ok
    end
  end

  defp validate_gtd_poll_start(payload) do
    with :ok <- require_string(payload, "name"),
         :ok <- optional_integer(payload, "vote_budget_per_bot", 1, 100),
         :ok <- optional_map(payload, "snapshot") do
      :ok
    end
  end

  defp validate_gtd_poll_vote_submit(payload) do
    with :ok <- require_string(payload, "poll_id"),
         :ok <- require_string(payload, "voter_id"),
         :ok <- optional_string(payload, "voter_type"),
         :ok <- require_list(payload, "allocations") do
      :ok
    end
  end

  defp validate_gtd_poll_id_only(payload) do
    require_string(payload, "poll_id")
  end

  defp require_schema_version_1_0(payload) do
    case Map.get(payload, "schema_version") do
      "1.0" -> :ok
      _ -> {:error, {:invalid_schema_version, Map.get(payload, "schema_version")}}
    end
  end

  defp optional_map(payload, key) do
    case Map.get(payload, key) do
      nil -> :ok
      m when is_map(m) -> :ok
      _ -> {:error, {:invalid_map, key}}
    end
  end

  defp require_list(payload, key) do
    case Map.get(payload, key) do
      list when is_list(list) and list != [] -> :ok
      [] -> {:error, {:empty_list, key}}
      _ -> {:error, {:missing_or_invalid_list, key}}
    end
  end

  defp validate_empty(payload) do
    if map_size(payload) == 0, do: :ok, else: {:error, :payload_must_be_empty}
  end

  defp require_string(payload, key) do
    case Map.get(payload, key) do
      value when is_binary(value) ->
        if String.trim(value) != "", do: :ok, else: {:error, {:missing_or_invalid_string, key}}

      _ ->
        {:error, {:missing_or_invalid_string, key}}
    end
  end

  defp optional_string(payload, key) do
    case Map.get(payload, key) do
      nil -> :ok
      value when is_binary(value) -> :ok
      _ -> {:error, {:invalid_string, key}}
    end
  end

  defp optional_string_list(payload, key) do
    case Map.get(payload, key) do
      nil ->
        :ok

      values when is_list(values) ->
        if Enum.all?(values, &is_binary/1), do: :ok, else: {:error, {:invalid_string_list, key}}

      _ ->
        {:error, {:invalid_string_list, key}}
    end
  end

  defp optional_boolean(payload, key) do
    case Map.get(payload, key) do
      nil -> :ok
      value when is_boolean(value) -> :ok
      _ -> {:error, {:invalid_boolean, key}}
    end
  end

  defp optional_enum(payload, key, allowed) do
    case Map.get(payload, key) do
      nil ->
        :ok

      value ->
        if Enum.member?(allowed, value), do: :ok, else: {:error, {:invalid_enum, key, allowed}}
    end
  end

  defp optional_integer(payload, key, min, max) do
    case Map.get(payload, key) do
      nil ->
        :ok

      value when is_integer(value) and value >= min and value <= max ->
        :ok

      _ ->
        {:error, {:invalid_integer_range, key, min, max}}
    end
  end
end
