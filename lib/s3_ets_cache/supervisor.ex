defmodule S3EtsCache.Supervisor do
  use Supervisor
  require Logger

  def start_link do
    Supervisor.start_link(__MODULE__, :ok)
  end

  @event_manager S3EtsCache.EventManager
  @registry_name S3EtsCache.FileRegistry
  @files_supervisor S3EtsCache.FileSupervisor

  def init(:ok) do
    children = [
      worker(GenEvent, [[name: @event_manager]]),
      supervisor(S3EtsCache.FileSupervisor, [@event_manager, [name: @files_supervisor]]),
      worker(S3EtsCache.FileRegistry, [@files_supervisor, [name: @registry_name]])
    ]
    :ets.new(S3EtsCache, [:named_table, :public])

    Logger.info("Starting S3EtsCache")

    supervise(children, strategy: :one_for_one)
  end
end
