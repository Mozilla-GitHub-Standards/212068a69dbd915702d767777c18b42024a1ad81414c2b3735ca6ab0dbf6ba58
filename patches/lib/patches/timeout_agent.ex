defmodule Patches.Timeout.Agent.Config do
  @moduledoc """
  A structure containing configuration options for a `Patches.Timeout.Agent`.
  """

  defstruct(
    timeout: 30,
    sleep: 5
  )
end

defmodule Patches.Timeout.Agent do
  @moduledoc """
  """

  use Agent

  alias Patches.Timeout.Agent.Config
  alias Patches.StreamRegistry.Agent, as: RegistryAgent
  alias Patches.Server.Agent, as: ServerAgent

  @doc """
  Start and link to a new agent.
  """
  def start_link(config \\ %Config{}) do
    init =
      %{
        state: :not_started,
        config: config,
        sessions: %{},
      }

    Agent.start_link(fn -> init end, name: __MODULE__)
  end

  @doc """
  Instruct the agent to start checking session timeouts.
  
  This function will block the calling process indefinitely, and so
  should be called in its own process via `spawn/1`.
  """
  def run() do
    time_to_sleep =
      Agent.get(__MODULE__, fn %{ config: %{ sleep: sleep } } -> sleep end)

    timed_out_sessions =
      Agent.get_and_update(__MODULE__, fn
        state=%{ state: :stopped } ->
          {[], state}

        state=%{ sessions: sessions, config: config } ->
          timed_out =
            sessions
            |> Enum.filter(fn {_id, lhf} -> timed_out?(lhf, config.timeout) end)
            |> Enum.map(fn {id, _lhf} -> id end)

          new_sessions =
            sessions
            |> Enum.filter(fn {id, _lhf} -> Enum.find(timed_out, &( id == &1 )) == nil end)
            |> Enum.into(%{})

          {timed_out, %{ state | sessions: new_sessions }}
      end)
    
    Enum.each(timed_out_sessions, fn session_id ->
      RegistryAgent.terminate_session(session_id)
      ServerAgent.terminate_session(session_id)
    end)

    :timer.sleep(time_to_sleep * 1000)
    run()
  end

  @doc """
  Instruct the agent to stop checking session timeouts.
  """
  def stop() do
    Agent.update(__MODULE__, &Map.put(&1, :state, :stopped))
  end

  @doc """
  Record the fact that a particular session was found to be active.

  Returns the last time the session was heard from.
  """
  def notify_activity(session: session_id) when is_binary(session_id) do
    Agent.get_and_update(__MODULE__, fn log=%{ sessions: sessions } ->
      last_heard_from =
        case Map.get(sessions, session_id) do
          nil ->
            Time.utc_now()

          last_heard_from ->
            last_heard_from
        end

      new_log =
        %{ log | sessions: Map.put(sessions, session_id, Time.utc_now()) }

      {last_heard_from, new_log}
    end)
  end

  @doc """
  Lookup a session ID to find the last time it was heard from.
  """
  def last_heard_from(session_id) do
    Agent.get(__MODULE__, fn
      %{ sessions: %{ ^session_id => last_heard_from } } ->
        last_heard_from

      _ ->
        nil
    end)
  end

  @doc """
  Determine if a session has timed out given the last time it was heard from
  and a number of seconds after which a session should be considered to have
  timed out.
  """
  def timed_out?(last_heard_from, timeout_seconds) do
    timed_out =
      last_heard_from
      |> Time.add(timeout_seconds)
      |> Time.compare(Time.utc_now())

    timed_out != :gt
  end
end
