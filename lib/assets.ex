defmodule Boom.Assets do
  use Scenic.Assets.Static,
    otp_app: :boom,
    sources: [
      "assets",
      {:scenic, "deps/scenic/assets"}
    ],
    alias: [
      roboto_bold: "fonts/Roboto-Bold.ttf"
    ]
end
