defmodule Boom.Server.Session do
  use GenServer
  require Logger

  alias Boom.Command
  alias Boom.CommandParser

  defmodule State do
    @enforce_keys [:id, :port, :peer, :log_prefix]
    defstruct(@enforce_keys)
  end

  def child_spec(opts) do
    super(opts)
    |> Map.put(:restart, :temporary)
  end

  def start_link(opts) do
    {id, opts} = Keyword.pop!(opts, :id)
    {port, opts} = Keyword.pop!(opts, :port)
    GenServer.start_link(__MODULE__, {id, port}, opts)
  end

  @impl true
  def init({id, port}) do
    {:ok, peername} = :inet.peername(port)
    {:ok, sockname} = :inet.sockname(port)
    peer = describe_peer(peername, sockname)

    log_prefix = "[#{inspect(__MODULE__)} #{id}] "
    Logger.info(log_prefix <> "Received connection from #{peer}.")

    send(self(), :banner)
    PubSub.subscribe(self(), :sessions)

    {:ok,
     %State{
       id: id,
       port: port,
       peer: peer,
       log_prefix: log_prefix
     }}
  end

  @impl true
  def handle_info({:tcp, port, json}, %State{port: port, log_prefix: log_prefix} = state) do
    %{"type" => "cmd", "text" => cmd} = Jason.decode!(json)
    Logger.debug(log_prefix <> "Command: #{inspect(cmd)}")

    run_command(cmd)
    {:noreply, state}
  end

  @impl true
  def handle_info(
        {:tcp_closed, port},
        %State{port: port, peer: peer, log_prefix: log_prefix} = state
      ) do
    Logger.info(log_prefix <> "Lost connection from #{peer}.")
    {:stop, :normal, state}
  end

  @impl true
  def handle_info({:output, message}, %State{port: port} = state) do
    %{"type" => "out", "text" => message}
    |> Jason.encode!()
    |> then(&:gen_tcp.send(port, &1 <> "\n"))

    {:noreply, state}
  end

  @impl true
  def handle_info(:banner, %State{port: port} = state) do
    %{"type" => "banner", "text" => generate_banner()}
    |> Jason.encode!()
    |> then(&:gen_tcp.send(port, &1 <> "\n"))

    {:noreply, state}
  end

  defp describe_peer({:local, _}, {:local, path}) when is_binary(path), do: path

  defp describe_peer({addr, port}, _) do
    cond do
      :inet.is_ipv6_address(addr) -> "#{:inet.ntoa(addr)} port #{port}"
      :inet.is_ipv4_address(addr) -> "#{:inet.ntoa(addr)}:#{port}"
    end
  end

  defp generate_banner do
    object_count = Boom.ObjectRegistry.count()
    obs_count = Boom.ObservationLog.count_all()

    [
      "BOOM: System is online.\n",
      if object_count == 0 && obs_count == 0 do
        "No observations have been logged yet, and no objects are known.\n"
      else
        [
          "Known objects: #{object_count}\n",
          "Observations:  #{obs_count}\n"
        ]
      end,
      "Ready for input ..."
    ]
    |> IO.iodata_to_binary()
  end

  defp run_command(command) do
    case CommandParser.parse(command) do
      {:ok, %Command{} = cmd} -> Command.run(cmd)
      {:error, :unknown_command} -> output_local("Unknown command.")
    end
  end

  defp output_local(iodata) when is_binary(iodata) or is_list(iodata) do
    iodata
    |> IO.iodata_to_binary()
    |> then(&send(self(), {:output, &1}))
  end
end
