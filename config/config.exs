# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
import Config

# connect the app's asset module to Scenic
config :scenic, :assets, module: Boom.Assets

# Configure the main viewport for the Scenic application
config :boom, :viewport,
  name: :main_viewport,
  size: {800, 600},
  theme: :dark,
  default_scene: Boom.Scene.Home,
  drivers: [
    [
      module: Scenic.Driver.Local,
      name: :local,
      window: [resizeable: false, title: "boom"],
      on_close: :stop_system
    ]
  ]

config :boom, ecto_repos: [Boom.DB.Repo]

config :boom, Boom.DB.Repo,
  database: "boom",
  hostname: "localhost",
  port: "5432",
  types: Boom.PostgresTypes
