defmodule Pristine.Adapters.Compression.Gzip do
  @moduledoc """
  Gzip compression adapter using Erlang's :zlib module.

  Provides gzip compression and decompression for request/response bodies.
  """

  @behaviour Pristine.Ports.Compression

  @impl true
  @doc """
  Compresses binary data using gzip.

  ## Options

  - `:level` - Compression level (currently ignored, uses default)

  ## Examples

      iex> {:ok, compressed} = Pristine.Adapters.Compression.Gzip.compress("hello")
      iex> is_binary(compressed)
      true
  """
  def compress(data, _opts \\ []) when is_binary(data) do
    {:ok, :zlib.gzip(data)}
  end

  @impl true
  @doc """
  Decompresses gzip-encoded binary data.

  ## Options

  Currently no options are supported.

  ## Examples

      iex> compressed = :zlib.gzip("hello")
      iex> Pristine.Adapters.Compression.Gzip.decompress(compressed)
      {:ok, "hello"}

      iex> Pristine.Adapters.Compression.Gzip.decompress("invalid")
      {:error, :invalid_gzip_data}
  """
  def decompress(data, _opts \\ []) when is_binary(data) do
    {:ok, :zlib.gunzip(data)}
  rescue
    ErlangError -> {:error, :invalid_gzip_data}
    ArgumentError -> {:error, :invalid_gzip_data}
  end

  @impl true
  @doc """
  Returns the content encoding identifier for gzip.

  ## Examples

      iex> Pristine.Adapters.Compression.Gzip.content_encoding()
      "gzip"
  """
  def content_encoding, do: "gzip"
end
