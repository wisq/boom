defmodule Boom.Server do
  use GenServer
  require Logger

  alias Boom.Server.SessionSupervisor

  def start_link(opts) do
    {listen_on, opts} = Keyword.pop!(opts, :listen_on)
    opts = Keyword.put_new(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, listen_on, opts)
  end

  @log_prefix "[#{inspect(__MODULE__)}] "

  @listen_opts [
    :binary,
    packet: :raw,
    active: true,
    reuseaddr: true
  ]

  @impl true
  def init(spec) do
    {port, opts, desc} = listen_opts(spec)

    case :gen_tcp.listen(port, opts) do
      {:ok, socket} ->
        Logger.info(@log_prefix <> "Listening on #{desc}")
        send(self(), :accept)
        {:ok, socket}

      {:error, reason} ->
        Logger.critical("Failed to listen on #{desc}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def handle_info(:accept, socket) do
    {:ok, port} = :gen_tcp.accept(socket)

    {:ok, pid} = SessionSupervisor.start_session(port)
    :gen_tcp.controlling_process(port, pid)

    send(self(), :accept)
    {:noreply, socket}
  end

  defp listen_opts({:unix, path}) do
    case File.rm(path) do
      :ok -> :ok
      {:error, :enoent} -> :ok
    end

    opts = [:local, {:ifaddr, {:local, path}} | @listen_opts]
    {0, opts, "Unix domain socket at #{path}"}
  end
end
