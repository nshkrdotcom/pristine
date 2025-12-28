# Architecture Audit: Multipart File Handling

## _files.py -> Pristine/MultipartEx Mapping

**Date**: 2025-12-28
**Scope**: Mapping Python Tinker SDK file handling to Elixir Pristine/MultipartEx system

---

## 1. Summary

The Python Tinker SDK's `_files.py` provides a file handling abstraction that:

1. **Accepts diverse file input types**: bytes, IO streams, PathLike objects, and tuples containing filename/content/content-type/headers
2. **Transforms file inputs** for httpx multipart encoding
3. **Supports both sync and async** file reading via `anyio`
4. **Integrates with base_client.py** for multipart/form-data request construction
5. **Handles base64 file inputs** via `Base64FileInput` type guard

The Elixir MultipartEx library provides equivalent functionality with streaming support, while Pristine's adapter wraps it behind a port behaviour for pluggability.

---

## 2. Detailed Analysis

### 2.1 How _files.py Handles File Types

**Source**: `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/_files.py`

#### Type Definitions (from _types.py)

**Source**: `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/_types.py` (lines 43-72)

```python
# Python type hierarchy:
Base64FileInput = Union[IO[bytes], PathLike[str]]
FileContent = Union[IO[bytes], bytes, PathLike[str]]

FileTypes = Union[
    FileContent,                                           # file (or bytes)
    Tuple[Optional[str], FileContent],                     # (filename, file)
    Tuple[Optional[str], FileContent, Optional[str]],      # (filename, file, content_type)
    Tuple[Optional[str], FileContent, Optional[str], Mapping[str, str]],  # + headers
]

RequestFiles = Union[Mapping[str, FileTypes], Sequence[Tuple[str, FileTypes]]]
```

#### Type Guards

**Source**: `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/_files.py` (lines 23-38)

```python
def is_base64_file_input(obj: object) -> TypeGuard[Base64FileInput]:
    return isinstance(obj, io.IOBase) or isinstance(obj, os.PathLike)

def is_file_content(obj: object) -> TypeGuard[FileContent]:
    return (
        isinstance(obj, bytes) or
        isinstance(obj, tuple) or
        isinstance(obj, io.IOBase) or
        isinstance(obj, os.PathLike)
    )
```

#### File Transform Logic

**Source**: `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/_files.py` (lines 63-80)

```python
def _transform_file(file: FileTypes) -> HttpxFileTypes:
    if is_file_content(file):
        if isinstance(file, os.PathLike):
            path = pathlib.Path(file)
            return (path.name, path.read_bytes())  # Extracts filename from path
        return file

    if is_tuple_t(file):
        return (file[0], read_file_content(file[1]), *file[2:])  # Preserves tuple structure

    raise TypeError(...)

def read_file_content(file: FileContent) -> HttpxFileContent:
    if isinstance(file, os.PathLike):
        return pathlib.Path(file).read_bytes()
    return file
```

**Key behaviors**:
1. PathLike objects are read synchronously into bytes with filename extraction
2. Tuple structures are preserved while content is read
3. IO streams and bytes pass through unchanged

### 2.2 Base64 Encoding Patterns

The `Base64FileInput` type is defined but **not actively used** in `_files.py`. Base64 encoding is handled elsewhere in the SDK when needed for specific API endpoints. The type guard `is_base64_file_input()` exists to identify inputs that could be base64-encoded.

**Key observation**: MultipartEx does not currently have dedicated base64 encoding helpers for file content.

### 2.3 Multipart Form Construction

**Source**: `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/_base_client.py` (lines 450-494)

```python
# In _build_request():
content_type = headers.get("Content-Type")
files = options.files

# If multipart/form-data header is set:
if content_type is not None and content_type.startswith("multipart/form-data"):
    if "boundary" not in content_type:
        headers.pop("Content-Type")  # Let httpx generate boundary

    if json_data:
        kwargs["data"] = self._serialize_multipartform(json_data)  # Serialize nested data

    # Force multipart even with no files
    if not files:
        files = cast(HttpxRequestFiles, ForceMultipartDict())

kwargs["files"] = files
```

**Form serialization** (lines 513-541):
```python
def _serialize_multipartform(self, data: Mapping[object, object]) -> dict[str, object]:
    items = self.qs.stringify_items(data, array_format="brackets")
    serialized: dict[str, object] = {}
    for key, value in items:
        existing = serialized.get(key)
        if not existing:
            serialized[key] = value
        elif is_list(existing):
            existing.append(value)
        else:
            serialized[key] = [existing, value]
    return serialized
```

**Key behaviors**:
1. Uses bracket notation (`array[]`) for nested/array data
2. ForceMultipartDict trick forces httpx to use multipart encoding
3. Boundary generation delegated to httpx when not explicit

### 2.4 Content-Type Detection

The Python SDK **does not perform content-type detection** - it relies on:
1. User-provided content-type in the tuple
2. httpx's default behavior
3. Server-side inference

---

## 3. Pristine/MultipartEx Equivalent

### 3.1 Pristine Port & Adapter

**Source**: `/home/home/p/g/n/pristine/lib/pristine/ports/multipart.ex` (lines 1-7)

```elixir
defmodule Pristine.Ports.Multipart do
  @moduledoc """
  Multipart encoding boundary.
  """

  @callback encode(term(), keyword()) :: {binary(), iodata() | Enumerable.t()}
end
```

**Source**: `/home/home/p/g/n/pristine/lib/pristine/adapters/multipart/ex.ex` (lines 1-12)

```elixir
defmodule Pristine.Adapters.Multipart.Ex do
  @behaviour Pristine.Ports.Multipart

  @impl true
  def encode(payload, opts \\ []) do
    Multipart.encode(payload, opts)
  end
end
```

**Current state**: Minimal adapter - passes through to MultipartEx with no enhancement.

### 3.2 MultipartEx Library

#### Main Module

**Source**: `/home/home/p/g/n/multipart_ex/lib/multipart.ex`

```elixir
defstruct parts: [],
          boundary: nil,
          preamble: nil,
          epilogue: nil

@spec encode(t() | form() | [Part.t()], keyword()) :: {binary(), iodata() | Enumerable.t()}
def encode(input, opts \\ []) do
  input
  |> build(opts)
  |> Encoder.encode()
end
```

#### File Handling

**Source**: `/home/home/p/g/n/multipart_ex/lib/multipart/files.ex` (lines 8-43)

```elixir
@type file_input ::
        {:path, Path.t()}                                        # File path
        | {:content, iodata() | Enumerable.t(), binary()}        # Content with filename
        | {binary(), iodata() | Enumerable.t()}                  # (filename, content)
        | {binary(), iodata() | Enumerable.t(), binary()}        # + content_type
        | {binary(), iodata() | Enumerable.t(), binary(), Part.headers()}  # + headers

def to_part(name, input, opts \\ []) do
  case input do
    {:path, path} -> from_path(name, path, opts)
    {:content, content, filename} -> from_content(name, filename, content, opts)
    {filename, content} -> from_content(name, filename, content, opts)
    {filename, content, content_type} -> from_content(name, filename, content, Keyword.put(opts, :content_type, content_type))
    {filename, content, content_type, headers} -> ...
    _ -> raise ArgumentError, "unsupported file input: #{inspect(input)}"
  end
end
```

#### Content-Type Inference

**Source**: `/home/home/p/g/n/multipart_ex/lib/multipart/files.ex` (lines 48-55)

```elixir
@default_content_type "application/octet-stream"

def infer_content_type(filename) do
  if Code.ensure_loaded?(MIME) and function_exported?(MIME, :from_path, 1) do
    MIME.from_path(filename)
  else
    @default_content_type
  end
end
```

**Advantage over Python**: MultipartEx can infer content-type from filename if the `mime` library is available.

#### Streaming Support

**Source**: `/home/home/p/g/n/multipart_ex/lib/multipart/files.ex` (lines 57-66)

```elixir
defp from_path(name, path, opts) do
  filename = Path.basename(path)
  chunk_size = Keyword.get(opts, :chunk_size, @default_chunk_size)  # 64KB default
  stream = File.stream!(path, chunk_size, [])
  size = File.stat!(path).size
  # ...
end
```

**Advantage over Python**: Native streaming support for large files.

#### Form Serialization

**Source**: `/home/home/p/g/n/multipart_ex/lib/multipart/form.ex` (lines 21-29, 64-103)

```elixir
@type strategy :: :bracket | :dot | :flat
@type list_format :: :repeat | :index | :dot_index

def serialize(form, opts \\ []) do
  options = normalize_options(opts)  # strategy: :bracket, list_format: :repeat, nil: :skip
  # ...
end

defp join_key(prefix, key, :bracket), do: prefix <> "[" <> key <> "]"
defp join_key(prefix, key, :dot), do: prefix <> "." <> key
```

**Advantage over Python**: More flexible serialization strategies.

### 3.3 Tinkex Elixir Implementation (Existing Port)

Tinkex has its own parallel implementation:

#### File Types

**Source**: `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/files/types.ex`

```elixir
@type file_content :: binary() | Path.t() | File.Stream.t() | iodata()
@type file_tuple ::
        {String.t() | nil, file_content()}
        | {String.t() | nil, file_content(), String.t() | nil}
        | {String.t() | nil, file_content(), String.t() | nil, headers()}
```

#### Transform Logic

**Source**: `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/files/transform.ex` (lines 14-26)

```elixir
def transform_file(file) do
  cond do
    Types.file_content?(file) -> transform_content(file)
    match?({_, _}, file) or match?({_, _, _}, file) or match?({_, _, _, _}, file) ->
      transform_tuple(file)
    true -> {:error, {:invalid_file_type, file}}
  end
end
```

#### Multipart Encoding

**Source**: `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/multipart/encoder.ex`

```elixir
def encode_multipart(form_fields, files, boundary \\ nil) when is_map(form_fields) do
  resolved_boundary = boundary || generate_boundary()
  with {:ok, parts} <- encode_parts(resolved_boundary, form_fields, files) do
    body = IO.iodata_to_binary([parts, "--", resolved_boundary, "--", @crlf])
    {:ok, body, "multipart/form-data; boundary=#{resolved_boundary}"}
  end
end
```

**Note**: Tinkex's implementation does NOT stream - it builds the entire body in memory.

---

## 4. Gap Analysis

### 4.1 Features Present in Python, Missing/Limited in MultipartEx

| Feature | Python _files.py | MultipartEx | Tinkex Files | Gap |
|---------|-----------------|-------------|--------------|-----|
| PathLike/Path support | Yes (via pathlib) | Yes ({:path, path}) | Yes (Path.t()) | None |
| IO stream support | Yes (io.IOBase) | Yes (Enumerable.t()) | Yes (File.Stream) | None |
| Bytes/binary support | Yes | Yes (iodata) | Yes | None |
| Tuple variants | 4 variants | 5 variants | 4 variants | None |
| Async file reading | Yes (anyio) | No explicit | Task.async wrapper | **Minor** |
| Base64 encoding | Type guard only | None | None | **Minor** |
| Content-type inference | None (httpx default) | Via MIME lib | None | MultipartEx better |
| Streaming large files | No (reads all) | Yes (File.stream!) | No | MultipartEx better |
| ForceMultipart trick | Yes | N/A (explicit) | N/A | N/A |

### 4.2 Features in MultipartEx Not Used by Pristine Adapter

| Feature | MultipartEx | Pristine Adapter |
|---------|-------------|------------------|
| Streaming body | Yes | **Not exposed** |
| Content-length calc | Yes | **Not exposed** |
| Custom preamble/epilogue | Yes | **Not exposed** |
| Strategy options | :bracket, :dot, :flat | **Not exposed** |
| List format options | :repeat, :index, :dot_index | **Not exposed** |
| Nil handling options | :skip, :empty | **Not exposed** |
| Finch adapter | Yes | **Not used** |
| Req adapter | Yes | **Not used** |

### 4.3 Gaps in Pristine Adapter

1. **No options passthrough**: The adapter ignores opts and doesn't expose MultipartEx's rich configuration
2. **No streaming integration**: Pristine's HTTP client integration doesn't leverage streaming
3. **No content-length header**: Important for progress tracking and server optimization
4. **No type conversion helpers**: Unlike Tinkex, no file input normalization layer

### 4.4 Gaps in MultipartEx Itself

1. **No explicit async API**: Unlike Python's `async_to_httpx_files()`, no async helpers
2. **No base64 encoding utilities**: May be needed for some API endpoints
3. **No file input validation module**: Unlike Tinkex.Files.Types type guards
4. **No unified transform API**: Unlike Tinkex.Files.Transform that normalizes inputs

---

## 5. Recommended Changes

### 5.1 MultipartEx Enhancements

#### Add File Input Validation Module

```elixir
# lib/multipart/validation.ex
defmodule Multipart.Validation do
  @moduledoc "Type guards and validation for file inputs"

  @spec file_content?(term()) :: boolean()
  def file_content?(content) when is_binary(content), do: true
  def file_content?(%File.Stream{}), do: true
  def file_content?(content) when is_list(content), do: iodata?(content)
  def file_content?(content), do: Enumerable.impl_for(content) != nil

  @spec valid_file_input?(term()) :: boolean()
  def valid_file_input?({:path, path}) when is_binary(path), do: true
  def valid_file_input?({:content, content, filename})
    when is_binary(filename), do: file_content?(content)
  # ... etc
end
```

#### Add Base64 Utilities (Optional)

```elixir
# lib/multipart/base64.ex
defmodule Multipart.Base64 do
  @moduledoc "Base64 encoding utilities for file content"

  @spec encode_file(Path.t() | binary()) :: {:ok, binary()} | {:error, term()}
  def encode_file(path) when is_binary(path) and byte_size(path) > 0 do
    with {:ok, content} <- File.read(path) do
      {:ok, Base.encode64(content)}
    end
  end

  @spec encode_content(iodata()) :: binary()
  def encode_content(content), do: Base.encode64(IO.iodata_to_binary(content))
end
```

### 5.2 Pristine Adapter Improvements

#### Expose Full Options

```elixir
defmodule Pristine.Adapters.Multipart.Ex do
  @behaviour Pristine.Ports.Multipart

  @impl true
  def encode(payload, opts \\ []) do
    Multipart.encode(payload, normalize_opts(opts))
  end

  @doc "Build multipart with streaming body and headers"
  def build_streaming(payload, opts \\ []) do
    multipart = Multipart.build(payload, normalize_opts(opts))
    headers = Multipart.Encoder.headers(multipart)
    {_, body} = Multipart.Encoder.encode(multipart)
    stream = Multipart.Encoder.to_stream(body)

    {headers, stream}
  end

  @doc "Get content length if determinable"
  def content_length(payload, opts \\ []) do
    payload
    |> Multipart.build(normalize_opts(opts))
    |> Multipart.content_length()
  end

  defp normalize_opts(opts) do
    Keyword.merge([
      strategy: :bracket,
      list_format: :repeat,
      nil: :skip
    ], opts)
  end
end
```

#### Add Port Callbacks

```elixir
defmodule Pristine.Ports.Multipart do
  @moduledoc "Multipart encoding port"

  @callback encode(term(), keyword()) :: {binary(), iodata() | Enumerable.t()}
  @callback build_streaming(term(), keyword()) :: {[{binary(), binary()}], Enumerable.t()}
  @callback content_length(term(), keyword()) :: {:ok, non_neg_integer()} | :unknown

  @optional_callbacks [build_streaming: 2, content_length: 2]
end
```

### 5.3 Add File Transform Layer to Pristine

Consider adding a Pristine.Files module similar to Tinkex:

```elixir
defmodule Pristine.Files do
  @moduledoc "File input transformation for multipart uploads"

  @type file_input ::
    binary() | Path.t() | File.Stream.t() |
    {binary() | nil, binary()} |
    {binary() | nil, binary(), binary() | nil} |
    {binary() | nil, binary(), binary() | nil, keyword()}

  @spec transform(file_input()) :: {:ok, Multipart.Files.file_input()} | {:error, term()}
  def transform(input) do
    # Normalize to MultipartEx expected format
  end

  @spec transform_async(file_input()) :: Task.t()
  def transform_async(input) do
    Task.async(fn -> transform(input) end)
  end
end
```

---

## 6. Concrete Next Steps

### Priority 1: Pristine Adapter Enhancement (TDD)

**Files to modify**:
- `/home/home/p/g/n/pristine/lib/pristine/ports/multipart.ex`
- `/home/home/p/g/n/pristine/lib/pristine/adapters/multipart/ex.ex`

**TDD Steps**:

1. **Test**: Write test for `build_streaming/2` returning headers and stream
   ```elixir
   test "build_streaming returns headers and enumerable body" do
     payload = %{name: "test", file: {:path, "test/fixtures/sample.txt"}}
     {headers, stream} = Pristine.Adapters.Multipart.Ex.build_streaming(payload)

     assert Enum.find(headers, fn {k, _} -> k == "content-type" end)
     assert Enumerable.impl_for(stream) != nil
   end
   ```

2. **Test**: Write test for `content_length/2`
   ```elixir
   test "content_length returns size for known-size parts" do
     payload = %{name: "test", file: {"test.txt", "content"}}
     assert {:ok, _length} = Pristine.Adapters.Multipart.Ex.content_length(payload)
   end
   ```

3. **Implement**: Add callbacks to port and adapter

### Priority 2: MultipartEx Validation Module (TDD)

**Files to create**:
- `/home/home/p/g/n/multipart_ex/lib/multipart/validation.ex`
- `/home/home/p/g/n/multipart_ex/test/multipart/validation_test.exs`

**TDD Steps**:

1. **Test**: Write tests for `file_content?/1` with various inputs
2. **Test**: Write tests for `valid_file_input?/1` with tuple variants
3. **Implement**: Module with type guards

### Priority 3: Pristine Files Module (TDD)

**Files to create**:
- `/home/home/p/g/n/pristine/lib/pristine/files.ex`
- `/home/home/p/g/n/pristine/lib/pristine/files/types.ex`
- `/home/home/p/g/n/pristine/lib/pristine/files/transform.ex`

**TDD Steps**:

1. **Test**: Write tests for path input transformation
2. **Test**: Write tests for tuple normalization
3. **Test**: Write tests for async transform
4. **Implement**: Based on Tinkex.Files pattern

### Priority 4: Base64 Utilities (Optional, TDD)

**Files to create**:
- `/home/home/p/g/n/multipart_ex/lib/multipart/base64.ex`
- `/home/home/p/g/n/multipart_ex/test/multipart/base64_test.exs`

**TDD Steps**:

1. **Test**: Write tests for `encode_file/1`
2. **Test**: Write tests for `encode_content/1`
3. **Implement**: Simple Base64 wrappers

---

## 7. File Reference Summary

### Python Tinker SDK
- `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/_files.py` - Core file handling
- `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/_types.py` - Type definitions
- `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/_base_client.py` - Multipart integration

### Pristine Elixir
- `/home/home/p/g/n/pristine/lib/pristine/ports/multipart.ex` - Multipart port behaviour
- `/home/home/p/g/n/pristine/lib/pristine/adapters/multipart/ex.ex` - MultipartEx adapter

### MultipartEx Library
- `/home/home/p/g/n/multipart_ex/lib/multipart.ex` - Main module
- `/home/home/p/g/n/multipart_ex/lib/multipart/files.ex` - File handling
- `/home/home/p/g/n/multipart_ex/lib/multipart/encoder.ex` - Encoding logic
- `/home/home/p/g/n/multipart_ex/lib/multipart/form.ex` - Form serialization
- `/home/home/p/g/n/multipart_ex/lib/multipart/part.ex` - Part structure
- `/home/home/p/g/n/multipart_ex/lib/multipart/boundary.ex` - Boundary generation
- `/home/home/p/g/n/multipart_ex/lib/multipart/adapter/finch.ex` - Finch integration
- `/home/home/p/g/n/multipart_ex/lib/multipart/adapter/req.ex` - Req integration

### Tinkex Elixir (Reference Implementation)
- `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/files/types.ex` - Type definitions
- `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/files/transform.ex` - Transform logic
- `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/files/reader.ex` - File reading
- `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/files/async_reader.ex` - Async wrapper
- `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/multipart/encoder.ex` - Multipart encoding
- `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/multipart/form_serializer.ex` - Form serialization
