defmodule WhipWhep.MixProject do
  use Mix.Project

  def project do
    [
      app: :whip_whep,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {WhipWhep, []}
    ]
  end

  defp deps do
    [
      {:plug, "~> 1.16"},
      {:bandit, "~> 1.5"},
      {:corsica, "~> 2.1"},
      {:jason, "~> 1.4"},
      {:ex_webrtc, "~> 0.6"},
      {:phoenix_pubsub, "~> 2.1"},
      {:websock_adapter, "~> 0.5"}
    ]
  end
end
