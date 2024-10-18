defmodule WhipWhep do
  use Application

  @ip Application.compile_env!(:whip_whep, :ip)
  @port Application.compile_env!(:whip_whep, :port)

  @impl true
  def start(_type, _args) do
    children = [
      {Bandit, plug: WhipWhep.Router, scheme: :http, ip: @ip, port: @port},
      {PartitionSupervisor,
        child_spec: DynamicSupervisor,
        name: WhipWhep.DynamicSupervisors},
      {Phoenix.PubSub, name: WhipWhep.PubSub},
      {Registry, name: __MODULE__.PeerRegistry, keys: :unique}
    ]

    Supervisor.start_link(children, strategy: :one_for_all, name: __MODULE__.Supervisor)
  end
end
