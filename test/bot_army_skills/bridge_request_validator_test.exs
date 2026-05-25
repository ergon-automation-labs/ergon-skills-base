defmodule BotArmySkills.BridgeRequestValidatorTest do
  use ExUnit.Case
  @moduletag :core

  alias BotArmySkills.BridgeRequestValidator

  test "accepts valid bridge.task.create payload" do
    payload = %{
      "title" => "Test task",
      "priority" => "normal",
      "context" => "inbox",
      "labels" => ["ops", "bridge"]
    }

    assert :ok = BridgeRequestValidator.validate("bridge.task.create", payload)
  end

  test "rejects invalid bridge.task.list limit" do
    assert {:error, {:invalid_integer_range, "limit", 1, 500}} =
             BridgeRequestValidator.validate("bridge.task.list", %{"limit" => 9999})
  end

  test "rejects non-empty bridge.system.fact payload" do
    assert {:error, :payload_must_be_empty} =
             BridgeRequestValidator.validate("bridge.system.fact", %{"unexpected" => true})
  end

  test "rejects missing query for bridge.internal_docs.query" do
    assert {:error, {:missing_or_invalid_string, "query"}} =
             BridgeRequestValidator.validate("bridge.internal_docs.query", %{"limit" => 5})
  end

  test "accepts bridge.chronicle.daily.brief with optional fields" do
    assert :ok =
             BridgeRequestValidator.validate("bridge.chronicle.daily.brief", %{
               "presentation" => "chronicle",
               "choice" => "stabilize",
               "task_limit" => 50,
               "live" => false
             })

    assert :ok = BridgeRequestValidator.validate("bridge.chronicle.daily.brief", %{})
  end

  test "rejects invalid presentation for bridge.chronicle.daily.brief" do
    assert {:error, {:invalid_enum, "presentation", _}} =
             BridgeRequestValidator.validate("bridge.chronicle.daily.brief", %{
               "presentation" => "tavern"
             })
  end

  test "accepts bridge.youtube.transcript.get with youtube_url" do
    assert :ok =
             BridgeRequestValidator.validate("bridge.youtube.transcript.get", %{
               "youtube_url" => "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
             })
  end

  test "accepts bridge.random.roll" do
    assert :ok =
             BridgeRequestValidator.validate("bridge.random.roll", %{
               "notation" => "2d6+1"
             })
  end

  test "rejects notation too short for bridge.random.roll" do
    assert {:error, {:notation_too_short, _}} =
             BridgeRequestValidator.validate("bridge.random.roll", %{"notation" => "d"})
  end

  test "accepts bridge.army.opinion.elicit" do
    assert :ok =
             BridgeRequestValidator.validate("bridge.army.opinion.elicit", %{
               "schema_version" => "1.0",
               "question" => "Ship Friday?"
             })
  end

  test "rejects opinion elicit without schema_version" do
    assert {:error, {:invalid_schema_version, _}} =
             BridgeRequestValidator.validate("bridge.army.opinion.elicit", %{
               "question" => "x"
             })
  end

  test "accepts bridge.gtd.poll.start with name" do
    assert :ok =
             BridgeRequestValidator.validate("bridge.gtd.poll.start", %{
               "name" => "round1",
               "snapshot" => %{"tasks" => []}
             })
  end
end
