defmodule Pristine.Ports.Compression do
  @moduledoc """
  Compression boundary for request/response payloads.

  Implementations handle encoding and decoding of compressed data,
  typically gzip for HTTP request/response bodies.
  """

  @doc """
  Compresses binary data.

  ## Options

  Options are implementation-specific. Common options may include:
  - `:level` - Compression level (implementation-dependent)

  ## Returns

  - `{:ok, compressed}` - Successfully compressed binary
  - `{:error, reason}` - Compression failed
  """
  @callback compress(binary(), keyword()) :: {:ok, binary()} | {:error, term()}

  @doc """
  Decompresses binary data.

  ## Options

  Options are implementation-specific.

  ## Returns

  - `{:ok, decompressed}` - Successfully decompressed binary
  - `{:error, reason}` - Decompression failed (e.g., invalid data)
  """
  @callback decompress(binary(), keyword()) :: {:ok, binary()} | {:error, term()}

  @doc """
  Returns the content encoding identifier for this compression type.

  Used for HTTP Content-Encoding headers.

  ## Examples

  - Gzip adapter returns `"gzip"`
  - Deflate adapter would return `"deflate"`
  """
  @callback content_encoding() :: String.t()
end
