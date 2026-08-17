defmodule Boom do
  @moduledoc """
  Starter application using the Scenic framework.
  """
  require Logger

  @default_port 2666

  def start(_type, _args) do
    # load the viewport configuration from config
    main_viewport_config =
      Application.get_env(:boom, :viewport)
      |> load_viewport_size()

    # start the application with the viewport
    children = [
      PubSub,
      Boom.DB.Repo,
      Boom.Grid,
      Boom.ObservationLog,
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

  defp listen_config, do: listen_config_from_env() || listen_config_from_app()

  defp listen_config_from_env do
    case System.get_env("BOOM_LISTEN") do
      "UNIX:" <> path -> {:unix, path}
      "TCP4:" <> ip_port -> parse_tcp4(ip_port)
      "TCP6:" <> ip_port -> parse_tcp6(ip_port)
      nil -> nil
    end
  end

  defp listen_config_from_app do
    case Application.get_env(:boom, :listen_on, :guess) do
      {:unix, _} = unix -> unix
      {:tcp4, addr, port} -> {:tcp4, parse_ip(:v4, addr), parse_port(port)}
      {:tcp6, addr, port} -> {:tcp6, parse_ip(:v6, addr), parse_port(port)}
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
      {:tcp6, :loopback, @default_port}
    else
      {:error, _} -> {:tcp4, :loopback, @default_port}
    end
  end

  defp get_uid do
    {output, 0} = System.cmd("id", ["-u"])
    {uid, "\n"} = Integer.parse(output)
    uid
  end

  defp parse_tcp4(ip_port) do
    case String.split(ip_port, ":", parts: 2) do
      [ip, port] -> {:tcp4, parse_ip(:v4, ip), parse_port(port)}
      [ip] -> {:tcp4, parse_ip(:v4, ip), @default_port}
    end
  end

  defp parse_tcp6("[" <> ip_port) do
    case String.split(ip_port, "]", parts: 2) do
      [ip, ":" <> port] -> {:tcp6, parse_ip(:v6, ip), parse_port(port)}
      [ip, ""] -> {:tcp6, parse_ip(:v6, ip), @default_port}
    end
  end

  defp parse_tcp6(ip), do: parse_ip(:v6, ip)

  defp parse_ip(_, ""), do: :loopback
  defp parse_ip(_, "*"), do: :any

  defp parse_ip(:v4, addr) when is_tuple(addr) do
    case :inet.is_ipv4_address(addr) do
      true -> addr
      false -> raise "Not a valid IPv4 address: #{inspect(addr)}"
    end
  end

  defp parse_ip(:v4, str) when is_binary(str) do
    str
    |> String.to_charlist()
    |> :inet.parse_ipv4strict_address()
    |> then(fn
      {:ok, addr} -> addr
      {:error, _} -> raise "Not a valid IPv4 address: #{str}"
    end)
  end

  defp parse_ip(:v6, addr) when is_tuple(addr) do
    case :inet.is_ipv6_address(addr) do
      true -> addr
      false -> raise "Not a valid IPv6 address: #{inspect(addr)}"
    end
  end

  defp parse_ip(:v6, str) when is_binary(str) do
    str
    |> String.to_charlist()
    |> :inet.parse_ipv6strict_address()
    |> then(fn
      {:ok, addr} -> addr
      {:error, _} -> raise "Not a valid IPv6 address: #{str}"
    end)
  end

  defp parse_port(:default), do: @default_port
  defp parse_port(port) when is_integer(port), do: port

  defp parse_port(str) when is_binary(str) do
    case Integer.parse(str) do
      {port, ""} -> port
      _ -> raise "Not a valid port number: #{str}"
    end
  end
end
