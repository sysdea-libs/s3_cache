defmodule S3Cache.Supervisor do
  use Supervisor
  require Logger

  def start_link do
    Supervisor.start_link(__MODULE__, :ok)
  end

  @event_manager S3Cache.EventManager
  @registry_name S3Cache.FileRegistry
  @files_supervisor S3Cache.FileSupervisor

  def init(:ok) do
    children = [
      worker(GenEvent, [[name: @event_manager]]),
      supervisor(S3Cache.FileSupervisor, [@event_manager, [name: @files_supervisor]]),
      worker(S3Cache.FileRegistry, [@files_supervisor, [name: @registry_name]])
    ]
    :ets.new(S3Cache, [:named_table, :public])

    Logger.info("Starting S3Cache")

    supervise(children, strategy: :one_for_one)
  end
end
