defmodule S3EtsCache do
  use Application

  # See http://elixir-lang.org/docs/stable/elixir/Application.html
  # for more information on OTP Applications
  def start(_type, _args) do
    S3EtsCache.Supervisor.start_link
  end

  def touch(file) do
    S3EtsCache.FileRegistry.touch(file)
  end

  def get(file) do
    case :ets.lookup(S3EtsCache, file) do
      [] -> S3EtsCache.request_file(file)
      [{_, v}] -> v
    end
  end

  def request_file(file) do
    pid = S3EtsCache.FileRegistry.lookup(file)
    GenServer.call pid, :get
  end
end
