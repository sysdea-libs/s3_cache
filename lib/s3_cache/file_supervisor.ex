defmodule S3Cache.FileSupervisor do
  use Supervisor
  require Logger

  def start_link(event_manager, opts \\ []) do
    Supervisor.start_link(__MODULE__, {event_manager}, opts)
  end

  def init({event_manager}) do
    children = [
      worker(S3Cache.File, [S3Cache, event_manager], restart: :temporary)
    ]

    Logger.info("Starting S3Cache.FileSupervisor")

    supervise(children, strategy: :simple_one_for_one)
  end
end
