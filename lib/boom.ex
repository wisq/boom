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

    # start the application with the viewport
    children = [
      PubSub,
      Boom.GeoEngine,
      Boom.CommandLog,
      {Scenic, [main_viewport_config]}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
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
end
