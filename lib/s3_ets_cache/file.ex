defmodule S3EtsCache.File do
  use GenServer

  @error_timeout 5 * 1000
  @fresh_timeout 60 * 1000
  @missing_timeout 5 * 60 * 1000

  def start_link(table, event_manager, file, opts \\ []) do
    GenServer.start_link(__MODULE__, {table, file, event_manager}, opts)
  end

  def init({table, file, event_manager}) do
    {:ok, %{file: file,
            timestamp: nil,
            table: table,
            etag: nil,
            inc_data: nil,
            inc_id: start_req(file, nil),
            inc_etag: nil,
            waiting: [],
            event_manager: event_manager}}
  end

  def handle_call(:get, _from, state) do
    case :ets.lookup(S3EtsCache, state.file) do
      [] -> {:noreply, %{state | waiting: [_from | state.waiting]}}
      [{_, v}] -> v
    end
  end

  def queue_fetch(t) do
    :erlang.send_after(t, self, :fetch)
  end

  def handle_info(v, state) do
    id = state.inc_id

    case v do
      # Init a new fetch
      %HTTPoison.AsyncStatus{id: ^id, code: 200} ->
        {:noreply, %{state | inc_data: ""}}

      # Same as cached
      %HTTPoison.AsyncStatus{id: ^id, code: 304} ->
        :hackney.close(id)
        queue_fetch(@fresh_timeout) # 1 minute on cached

        {:noreply, %{state | inc_id: nil,
                             timestamp: :erlang.now}}

      %HTTPoison.AsyncStatus{id: ^id, code: 404} ->
        :hackney.close(id)
        queue_fetch(@missing_timeout) # 5 minutes on 404

        :ets.insert(state.table, {state.file, nil})

        {:noreply, %{state | timestamp: nil,
                             etag: nil,
                             inc_id: nil}}

      # Error code, retry in 10 seconds
      %HTTPoison.AsyncStatus{id: ^id, code: _code} ->
        :hackney.close(id)
        queue_fetch(@error_timeout) # 5 seconds on error

        {:noreply, %{state | inc_id: nil}}

      # Grab ETag from the headers
      %HTTPoison.AsyncHeaders{ headers: headers } ->
        {:noreply, %{state | inc_etag: headers["ETag"]}}

      # Stream data in
      %HTTPoison.AsyncChunk{id: ^id, chunk: _chunk} ->
        {:noreply, %{state | inc_data: state.inc_data <> _chunk}}

      # File complete, redownload in 5 minutes
      %HTTPoison.AsyncEnd{id: ^id} ->
        :hackney.close(id)
        queue_fetch(@fresh_timeout) # 1 minute on fresh

        :ets.insert(state.table, {state.file, state.inc_data})

        for pid <- state.waiting do
          GenServer.reply pid, state.inc_data
        end

        GenEvent.notify(state.event_manager, { :new_data,
                                               %{file: state.file,
                                                 data: state.inc_data} })

        {:noreply, %{state | timestamp: :erlang.now,
                             etag: state.inc_etag,
                             inc_data: nil,
                             inc_id: nil,
                             inc_etag: nil,
                             waiting: []}}

      %HTTPoison.Error{id: ^id, reason: _reason} ->
        queue_fetch(@error_timeout) # 5 seconds on error
        {:noreply, %{state | inc_data: nil, inc_id: nil}}

      %HTTPoison.Error{id: _id, reason: _reason} ->
        {:noreply, state}

      # Handle starting new requests
      :fetch ->
        case state.inc_id do
          nil -> {:noreply, %{state | inc_id: start_req(state.file, state.etag)}}
          _ -> {:noreply, state}
        end

      # Ignore anything else
      _ ->
        {:noreply, state}
    end
  end

  def start_req(file, etag) do
    case get_file(file, etag) do
      {:ok, id} -> id
      {:error, _error} ->
        queue_fetch(@error_timeout)
        nil
    end
  end

  # Authorised get
  def get_file(%{bucket: bucket, key: key, region: region, auth: auth}, etag) do
    url = "https://s3.amazonaws.com/#{bucket}/#{key}"
    case HTTPoison.get(url, gen_auth_header(region, bucket, key, etag, auth), [stream_to: self]) do
      {:ok, %HTTPoison.AsyncResponse{id: id}} -> {:ok, id}
      err -> err
    end
  end

  # Public get
  def get_file(%{bucket: bucket, key: key}, etag) do
    url = "https://s3.amazonaws.com/#{bucket}/#{key}"
    case HTTPoison.get(url, %{"if-none-match" => etag || "\"\""}, [stream_to: self]) do
      {:ok, %HTTPoison.AsyncResponse{id: id}} -> {:ok, id}
      err -> err
    end
  end

  def gen_auth_header(region, bucket, key, etag, auth) do

    {date_string, ts_string} = gen_date
    empty_hash = sha256("")
    scope = "#{date_string}/#{region}/s3/aws4_request"
    header_list = "host;if-none-match;x-amz-content-sha256;x-amz-date"

    c_request = """
    GET
    /#{bucket}/#{key}

    host:s3.amazonaws.com
    if-none-match:#{etag || "\"\""}
    x-amz-content-sha256:#{empty_hash}
    x-amz-date:#{ts_string}

    #{header_list}
    """ <> empty_hash

    string_to_sign = """
    AWS4-HMAC-SHA256
    #{ts_string}
    #{scope}
    """ <> sha256(c_request)

    { aws_key, aws_secret } = auth

    signature = hmac("AWS4" <> aws_secret, date_string)
                |> hmac(region)
                |> hmac("s3")
                |> hmac("aws4_request")
                |> hmac(string_to_sign)
                |> hex

    header = "AWS4-HMAC-SHA256 Credential=#{aws_key}/#{scope}" <>
             ",SignedHeaders=#{header_list},Signature=#{signature}"

    %{"Authorization" => header,
      "if-none-match" => etag || "\"\"",
      "x-amz-content-sha256" => empty_hash,
      "x-amz-date" => ts_string}
  end

  def hex(b), do: b |> Base.encode16 |> String.downcase
  def hmac(k, b), do: :crypto.hmac(:sha256, k, b)
  def sha256(b), do: :crypto.hash(:sha256, b) |> hex

  def gen_date do
    {{y, m, d}, {h, min, s}} = :calendar.now_to_universal_time(:erlang.now)
    datestamp = d2(y) <> d2(m) <> d2(d)
    timestamp = datestamp <> "T" <> d2(h) <> d2(min) <> d2(s) <> "Z"
    {datestamp, timestamp}
  end

  defp d2(n) when n < 10, do: "0" <> Integer.to_string(n)
  defp d2(n), do: Integer.to_string(n)
end
