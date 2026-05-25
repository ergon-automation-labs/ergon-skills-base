defmodule BotArmySkills.Actions.NatsRequestTest do
  use ExUnit.Case
  @moduletag :core

  alias BotArmySkills.Actions.NatsRequest

  describe "execute/2" do
    test "returns error when subject config is missing" do
      assert {:error, {:nats_request_failed, :missing_subject_config}} =
               NatsRequest.execute(%{}, %{"message" => %{}})
    end

    test "returns error when dynamic subject key is missing from payload" do
      config = %{"subject_key" => "bridge_subject", "allowed_subject_prefixes" => ["bridge."]}

      assert {:error, {:nats_request_failed, {:invalid_or_missing_subject, "bridge_subject"}}} =
               NatsRequest.execute(config, %{"message" => %{}})
    end

    test "rejects disallowed subject prefixes before network call" do
      config = %{
        "subject_key" => "bridge_subject",
        "allowed_subject_prefixes" => ["bridge."],
        "timeout_ms" => 500
      }

      payload = %{"bridge_subject" => "internal_docs.query", "message" => %{"query" => "test"}}

      assert {:error, {:nats_request_failed, {:subject_not_allowed, "internal_docs.query"}}} =
               NatsRequest.execute(config, payload)
    end

    test "validates bridge payload shape before network call when enabled" do
      config = %{
        "subject_key" => "bridge_subject",
        "payload_key" => "message",
        "allowed_subject_prefixes" => ["bridge."],
        "validate_bridge_schema" => true
      }

      payload = %{
        "bridge_subject" => "bridge.task.get",
        "message" => %{"task_id" => 123}
      }

      assert {:error, {:nats_request_failed, {:missing_or_invalid_string, "task_id"}}} =
               NatsRequest.execute(config, payload)
    end

    test "requires map payload at configured payload_key" do
      config = %{
        "subject_key" => "bridge_subject",
        "payload_key" => "message",
        "allowed_subject_prefixes" => ["bridge."]
      }

      payload = %{"bridge_subject" => "bridge.task.list", "message" => "not-a-map"}

      assert {:error, {:nats_request_failed, {:invalid_or_missing_payload, "message"}}} =
               NatsRequest.execute(config, payload)
    end
  end
end
