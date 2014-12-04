defmodule S3EtsCache.FileRegistry do
  use GenServer
  require Logger

  def start_link(s3files, opts \\ []) do
    GenServer.start_link(__MODULE__, {s3files}, opts)
  end

  def lookup(file) do
    GenServer.call(__MODULE__, {:lookup, file})
  end

  def touch(file) do
    GenServer.cast(__MODULE__, {:ensure, file})
  end

  def init({s3files}) do
    Logger.info("Starting S3EtsCache.FileRegistry")
    files = HashDict.new
    refs = HashDict.new
    {:ok, %{files: files, refs: refs, s3files: s3files}}
  end

  def handle_cast({:ensure, file}, state) do
    {_pid, state} = ensure_file(file, state)
    {:noreply, state}
  end

  def handle_call({:lookup, file}, _from, state) do
    {pid, state} = ensure_file(file, state)
    {:reply, pid, state}
  end

  defp ensure_file(file, state) do
    case HashDict.fetch(state.files, file) do
      {:ok, pid} -> {pid, state}
      :error ->
        {:ok, pid} = Supervisor.start_child(state.s3files, [file])
        ref = Process.monitor(pid)

        files = HashDict.put(state.files, file, pid)
        refs = HashDict.put(state.refs, ref, file)

        {pid, %{state | files: files, refs: refs}}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    {file, refs} = HashDict.pop(state.refs, ref)
    files = HashDict.delete(state.files, file)

    # Bring the File back up
    IO.puts "worker #{inspect file} died, respawning"
    handle_cast({:ensure, file}, %{state | files: files, refs: refs})
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end
end
