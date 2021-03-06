defmodule Patches.ServerTest do
  use ExUnit.Case
  doctest Patches.Server

  alias Patches.Server

  test "new sessions are queued upon creation" do
    %{ queued_sessions: queued } =
      Server.init()
      |> Server.queue_session("ubuntu:18.04", "testid")

    assert Enum.count(queued) == 1
  end

  test "can register sessions with unique identifiers" do
    %{ queued_sessions: queued } =
      Enum.reduce(0..3, Server.init(), fn (_n, server) ->
        server =
          Server.queue_session(server, "ubuntu:18.04", "testid")

        server
      end)

    ids =
      queued
      |> Map.keys()
      |> Enum.uniq()

    assert Enum.count(ids) == Enum.count(queued)
  end

  test "can replace active sessions with queued sessions" do
    {activated, server} =
      Enum.reduce(1..3, Server.init(), fn (n, server) ->
        Server.queue_session(server, "ubuntu:18.04", "testid#{n}")
      end)
      |> Server.activate_sessions(1)

    assert Enum.count(activated) == 1
    assert Enum.count(server.active_sessions) == 1
    assert Enum.count(server.queued_sessions) == 2
  end

  test "the most recently created sessions are activated first" do
    {_activated, server} =
      Enum.reduce(1..3, Server.init(), fn (n, server) ->
        Server.queue_session(server, "ubuntu:18.04", "testid#{n}")
      end)
      |> Server.activate_sessions(1)

    [ activated | _rest ] =
      server.active_sessions
      |> Enum.into([])
      |> Enum.map(fn {_id, session} -> session end)

    [ queued1 | [ queued2 | _rest ]] =
      server.queued_sessions
      |> Enum.into([])
      |> Enum.map(fn {_id, session} -> session end)

    assert activated.created_at < queued1.created_at
    assert activated.created_at < queued2.created_at
  end

  test "can support the full session lifecycle" do
    %{ active_sessions: active } =
      Server.init()
      |> Server.queue_session("ubuntu:18.04", "testid")
      |> Server.activate_sessions(1)
      |> (fn {_activated, server} -> server end).()
      |> Server.terminate_active_sessions()

    assert Enum.count(active) == 0
  end
end
