defmodule S3EtsCache.FileSupervisor do
  use Supervisor
  require Logger

  def start_link(event_manager, opts \\ []) do
    Supervisor.start_link(__MODULE__, {event_manager}, opts)
  end

  def init({event_manager}) do
    children = [
      worker(S3EtsCache.File, [S3EtsCache, event_manager], restart: :temporary)
    ]

    Logger.info("Starting S3EtsCache.FileSupervisor")

    supervise(children, strategy: :simple_one_for_one)
  end
end
