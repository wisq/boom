defmodule Boom do
  @moduledoc """
  Starter application using the Scenic framework.
  """
  require Logger

  def start(_type, _args) do
    # load the viewport configuration from config
    main_viewport_config =
      Application.get_env(:boom, :viewport)
      |> load_viewport_size()

    Boom.Grid.init()

    # start the application with the viewport
    children = [
      PubSub,
      Boom.GeoEngine,
      Boom.CommandLog,
      Boom.ObjectRegistry,
      Boom.ObjectSupervisor,
      Boom.Server.SessionSupervisor,
      {Boom.Server, listen_on: listen_config()},
      {Scenic, [main_viewport_config]}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end

  def output(iodata) when is_binary(iodata) or is_list(iodata) do
    text = IO.iodata_to_binary(iodata)
    PubSub.publish(:sessions, {:output, text})
  end

  def save_viewport_size({width, height}) do
    viewport_size_file()
    |> File.write!("#{width}:#{height}")
  end

  defp viewport_size_file do
    :code.priv_dir(:boom)
    |> Path.join("viewport_size.txt")
  end

  defp load_viewport_size(config) do
    with {:ok, data} <- viewport_size_file() |> File.read(),
         [wstr, hstr] <- String.split(data, ":"),
         {width, ""} <- Integer.parse(wstr),
         {height, ""} <- Integer.parse(hstr) do
      Logger.info("Loaded saved viewport size: #{width}x#{height}")
      Keyword.put(config, :size, {width, height})
    else
      _ -> config
    end
  end

  defp listen_config do
    case Application.get_env(:boom, :listen_on, :guess) do
      {:unix, _} = unix -> unix
      {:tcp, _, _} = tcp -> tcp
      :guess -> guess_listen_config()
    end
  end

  defp guess_listen_config do
    uid = get_uid()

    try_listen_unix("/run/user/#{uid}", "boom", uid) ||
      try_listen_unix("/tmp", "boom-#{uid}", uid) ||
      fallback_listen_tcp()
  end

  defp try_listen_unix(root, dir, my_uid) do
    path = Path.join(root, dir)

    with true <- File.dir?(root),
         :ok <- File.mkdir_p(path) do
      %File.Stat{uid: uid, mode: mode} = File.stat!(path)
      if uid != my_uid, do: raise("Not owned by you: #{inspect(path)}")

      new_mode = Bitwise.band(mode, 0o700)
      if new_mode != mode, do: File.chmod!(path, new_mode)

      {:unix, Path.join(path, "socket")}
    else
      _ -> nil
    end
  end

  defp fallback_listen_tcp do
    # Check if IPv6 is available.
    with {:ok, _} <- :inet.getaddr(~c'localhost', :inet6) do
      {:tcp6, :loopback, 2666}
    else
      {:error, _} -> {:tcp4, :loopback, 2666}
    end
  end

  defp get_uid do
    {output, 0} = System.cmd("id", ["-u"])
    {uid, "\n"} = Integer.parse(output)
    uid
  end
end
