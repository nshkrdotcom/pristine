# Client/Resource Layer Architecture Mapping: Tinker Python SDK to Pristine Elixir

**Date:** 2025-12-28
**Scope:** Deep architecture comparison of Tinker Python SDK client/resource patterns mapped to Pristine manifest-driven codegen

---

## 1. Executive Summary

The Tinker Python SDK follows a **Stainless SDK pattern**: a main client class (`AsyncTinker`) provides lazy-loaded resource namespaces (`models`, `sampling`, `training`, etc.), each resource class inherits from `AsyncAPIResource` which holds HTTP method references (`_get`, `_post`, etc.), and individual methods handle request building, serialization, and response casting.

Pristine follows a **manifest-driven execution pattern**: endpoints are declaratively defined in a manifest, a pipeline orchestrates transport/serialization/auth/retry/circuit-breaker, and codegen renders thin wrapper modules that delegate to `Pristine.Runtime.execute/5`.

**Key Finding:** Pristine's codegen produces minimal wrappers (just delegates to runtime), while Tinker's resources encode significant SDK behaviors (typed signatures, docstrings, request options, idempotency keys). To match Tinker's ergonomics, Pristine's codegen must be enhanced.

---

## 2. Tinker Python SDK Architecture

### 2.1 File Layout

| File | Purpose |
|------|---------|
| `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/_client.py` | Main client (`AsyncTinker`), resource registration, auth headers |
| `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/_base_client.py` | `BaseClient`, `AsyncAPIClient` with HTTP methods |
| `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/_resource.py` | `AsyncAPIResource` base class |
| `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/resources/*.py` | Individual resource modules |

### 2.2 Client Initialization Pattern

From `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/_client.py` (lines 50-108):

```python
class AsyncTinker(AsyncAPIClient):
    api_key: str

    def __init__(
        self,
        *,
        api_key: str | None = None,
        base_url: str | httpx.URL | None = None,
        timeout: Union[float, Timeout, None, NotGiven] = NOT_GIVEN,
        max_retries: int = DEFAULT_MAX_RETRIES,
        default_headers: Mapping[str, str] | None = None,
        default_query: Mapping[str, object] | None = None,
        http_client: httpx.AsyncClient | None = None,
        _strict_response_validation: bool = False,
    ) -> None:
        # API key from argument or TINKER_API_KEY env var
        if api_key is None:
            api_key = os.environ.get("TINKER_API_KEY")
        if api_key is None:
            raise TinkerError("The api_key client option must be set...")
        if not api_key.startswith("tml-"):
            raise TinkerError("The api_key must start with the 'tml-' prefix")

        # Base URL from argument or TINKER_BASE_URL or default
        if base_url is None:
            base_url = os.environ.get("TINKER_BASE_URL")
        if base_url is None:
            base_url = "https://tinker.thinkingmachines.dev/services/tinker-prod"
```

**Key patterns:**
1. Environment variable fallback for credentials
2. Credential validation (prefix check)
3. Configurable base URL with default
4. Timeout, retry, headers, query params all configurable
5. Optional custom httpx client injection

### 2.3 Resource Namespace Pattern

From `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/_client.py` (lines 109-148):

```python
@cached_property
def service(self) -> AsyncServiceResource:
    from .resources.service import AsyncServiceResource
    return AsyncServiceResource(self)

@cached_property
def training(self) -> AsyncTrainingResource:
    from .resources.training import AsyncTrainingResource
    return AsyncTrainingResource(self)

@cached_property
def models(self) -> AsyncModelsResource:
    from .resources.models import AsyncModelsResource
    return AsyncModelsResource(self)
```

**Pattern:** Lazy-loaded cached properties that instantiate resource classes on first access, passing `self` (the client) as context.

### 2.4 Base Resource Class

From `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/_resource.py` (lines 11-24):

```python
class AsyncAPIResource:
    _client: AsyncTinker

    def __init__(self, client: AsyncTinker) -> None:
        self._client = client
        self._get = client.get
        self._post = client.post
        self._patch = client.patch
        self._put = client.put
        self._delete = client.delete
        self._get_api_list = client.get_api_list
```

**Pattern:** Resource holds reference to client and aliases HTTP methods for convenience.

### 2.5 HTTP Method Implementation

From `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/_base_client.py` (lines 1164-1232):

```python
async def get(
    self,
    path: str,
    *,
    cast_to: Type[ResponseT],
    options: RequestOptions = {},
    stream: bool = False,
    stream_cls: type[_AsyncStreamT] | None = None,
) -> ResponseT | _AsyncStreamT:
    opts = FinalRequestOptions.construct(method="get", url=path, **options)
    return await self.request(cast_to, opts, stream=stream, stream_cls=stream_cls)

async def post(
    self,
    path: str,
    *,
    cast_to: Type[ResponseT],
    body: Body | None = None,
    files: RequestFiles | None = None,
    options: RequestOptions = {},
    stream: bool = False,
    stream_cls: type[_AsyncStreamT] | None = None,
) -> ResponseT | _AsyncStreamT:
    opts = FinalRequestOptions.construct(
        method="post",
        url=path,
        json_data=body,
        files=await async_to_httpx_files(files),
        **options,
    )
    return await self.request(cast_to, opts, stream=stream, stream_cls=stream_cls)
```

**Key elements:**
- `path` + `cast_to` type + `options` dict
- `body` for POST/PUT/PATCH
- `files` for multipart
- `stream` + `stream_cls` for SSE

### 2.6 Request Execution with Retry

From `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/_base_client.py` (lines 923-1045):

```python
async def request(
    self,
    cast_to: Type[ResponseT],
    options: FinalRequestOptions,
    *,
    stream: bool = False,
    stream_cls: type[_AsyncStreamT] | None = None,
) -> ResponseT | _AsyncStreamT:
    # ...
    for retries_taken in range(max_retries + 1):
        options = await self._prepare_options(options)
        request = self._build_request(options, retries_taken=retries_taken)

        try:
            response = await self._client.send(request, stream=stream)
        except httpx.TimeoutException as err:
            if remaining_retries > 0:
                await self._sleep_for_retry(...)
                continue
            raise APITimeoutError(request=request) from err

        try:
            response.raise_for_status()
        except httpx.HTTPStatusError as err:
            if remaining_retries > 0 and self._should_retry(err.response):
                await self._sleep_for_retry(...)
                continue
            raise self._make_status_error_from_response(err.response)
```

**Retry logic:**
- Exponential backoff with jitter
- Respects `Retry-After` header
- Retries on 408, 409, 429, 5xx
- `x-should-retry` header overrides

### 2.7 Resource Method Pattern

From `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/resources/models.py` (lines 18-66):

```python
class AsyncModelsResource(AsyncAPIResource):
    async def create(
        self,
        *,
        request: CreateModelRequest,
        extra_headers: Headers | None = None,
        extra_query: Query | None = None,
        extra_body: Body | None = None,
        timeout: float | httpx.Timeout | None | NotGiven = NOT_GIVEN,
        idempotency_key: str | None = None,
        max_retries: int | NotGiven = NOT_GIVEN,
    ) -> UntypedAPIFuture:
        """
        Creates a new model.

        Pass a LoRA config to create a new LoRA adapter for the base model.

        Args:
          request: The create model request containing base_model, user_metadata, and lora_config
          extra_headers: Send extra headers
          ...
        """
        options = make_request_options(
            extra_headers=extra_headers,
            extra_query=extra_query,
            extra_body=extra_body,
            timeout=timeout,
            idempotency_key=idempotency_key,
        )
        if max_retries is not NOT_GIVEN:
            options["max_retries"] = max_retries

        return await self._post(
            "/api/v1/create_model",
            body=model_dump(request, exclude_unset=True, mode="json"),
            options=options,
            cast_to=UntypedAPIFuture,
        )
```

**Pattern summary:**
1. Method signature has typed `request` param + request options
2. Docstring documents the operation and parameters
3. `make_request_options` builds the options dict
4. `model_dump` serializes the request pydantic model
5. `cast_to` specifies the response type

### 2.8 Error Handling Hierarchy

From `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/_client.py` (lines 234-265):

```python
def _make_status_error(
    self,
    err_msg: str,
    *,
    body: object,
    response: httpx.Response,
) -> APIStatusError:
    if response.status_code == 400:
        return _exceptions.BadRequestError(err_msg, response=response, body=body)
    if response.status_code == 401:
        return _exceptions.AuthenticationError(err_msg, response=response, body=body)
    if response.status_code == 403:
        return _exceptions.PermissionDeniedError(err_msg, response=response, body=body)
    if response.status_code == 404:
        return _exceptions.NotFoundError(err_msg, response=response, body=body)
    if response.status_code == 409:
        return _exceptions.ConflictError(err_msg, response=response, body=body)
    if response.status_code == 422:
        return _exceptions.UnprocessableEntityError(err_msg, response=response, body=body)
    if response.status_code == 429:
        return _exceptions.RateLimitError(err_msg, response=response, body=body)
    if response.status_code >= 500:
        return _exceptions.InternalServerError(err_msg, response=response, body=body)
```

**Pattern:** Status-code-specific exception types with request/response context.

### 2.9 Auth Headers

From `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/_client.py` (lines 164-168):

```python
@property
@override
def auth_headers(self) -> dict[str, str]:
    api_key = self.api_key
    return {"X-API-Key": api_key}
```

---

## 3. Pristine Elixir Architecture

### 3.1 File Layout

| File | Purpose |
|------|---------|
| `/home/home/p/g/n/pristine/lib/pristine/manifest.ex` | Manifest loading and validation |
| `/home/home/p/g/n/pristine/lib/pristine/manifest/endpoint.ex` | Endpoint struct definition |
| `/home/home/p/g/n/pristine/lib/pristine/core/context.ex` | Runtime context (adapters, config) |
| `/home/home/p/g/n/pristine/lib/pristine/core/pipeline.ex` | Request execution pipeline |
| `/home/home/p/g/n/pristine/lib/pristine/runtime.ex` | Runtime entrypoint |
| `/home/home/p/g/n/pristine/lib/pristine/codegen.ex` | Codegen orchestration |
| `/home/home/p/g/n/pristine/lib/pristine/codegen/elixir.ex` | Elixir code renderer |

### 3.2 Manifest Endpoint Definition

From `/home/home/p/g/n/pristine/lib/pristine/manifest/endpoint.ex` (lines 1-39):

```elixir
defmodule Pristine.Manifest.Endpoint do
  defstruct id: nil,
            method: nil,
            path: nil,
            request: nil,         # request type name
            response: nil,        # response type name
            retry: nil,           # retry policy key
            telemetry: nil,
            streaming: false,
            headers: %{},
            query: %{},
            body_type: nil,       # :json | :multipart | :raw
            content_type: nil,
            auth: nil,            # auth strategy key
            circuit_breaker: nil,
            rate_limit: nil
end
```

### 3.3 Context (Client Configuration Equivalent)

From `/home/home/p/g/n/pristine/lib/pristine/core/context.ex` (lines 1-66):

```elixir
defmodule Pristine.Core.Context do
  defstruct base_url: nil,
            headers: %{},
            auth: [],
            transport: nil,
            transport_opts: [],
            serializer: nil,
            multipart: nil,
            multipart_opts: [],
            retry: nil,
            retry_opts: [],
            rate_limiter: nil,
            rate_limit_opts: [],
            circuit_breaker: nil,
            circuit_breaker_opts: [],
            telemetry: nil,
            retry_policies: %{},
            type_schemas: %{}
```

**Comparison to Tinker:**
| Tinker `AsyncTinker` | Pristine `Context` |
|---------------------|-------------------|
| `api_key` | `auth` list (modules) |
| `base_url` | `base_url` |
| `timeout` | `transport_opts` |
| `max_retries` | `retry_opts` |
| `default_headers` | `headers` |
| `http_client` | `transport` (module) |
| N/A | `serializer`, `circuit_breaker`, `rate_limiter` |

### 3.4 Pipeline Execution

From `/home/home/p/g/n/pristine/lib/pristine/core/pipeline.ex` (lines 11-66):

```elixir
def execute(%Manifest{} = manifest, endpoint_id, payload, %Context{} = context, opts \\ []) do
  endpoint = Manifest.fetch_endpoint!(manifest, endpoint_id)

  # Resolve adapters from context
  serializer = context.serializer
  transport = context.transport
  retry = context.retry
  rate_limiter = context.rate_limiter
  circuit_breaker = context.circuit_breaker
  telemetry = context.telemetry

  # Build request
  with {:ok, {body, content_type}} <- encode_body(...),
       request <- build_request(endpoint, body, content_type, context, opts),
       result <- retry.with_retry(fn ->
         rate_limiter.within_limit(fn ->
           circuit_breaker.call(..., fn ->
             transport.send(request, context)
           end, ...)
         end, ...)
       end, ...),
       {:ok, response} <- normalize_transport_result(result),
       {:ok, data} <- serializer.decode(response.body, response_schema, opts) do
    {:ok, data}
  end
end
```

**Pipeline composition:**
```
telemetry.emit(:request_start)
  -> serializer.encode(payload)
    -> build_request(endpoint, body, headers, url)
      -> retry.with_retry(
           rate_limiter.within_limit(
             circuit_breaker.call(
               transport.send(request)
             )
           )
         )
        -> serializer.decode(response)
          -> telemetry.emit(:request_stop)
```

### 3.5 Current Codegen Output

From `/home/home/p/g/n/pristine/lib/pristine/codegen/elixir.ex` (lines 24-64):

```elixir
def render_client_module(module_name, manifest) do
  """
  defmodule #{module_name} do
    @moduledoc false

    @manifest #{inspect(manifest, pretty: true)}

    def manifest(), do: @manifest

  #{render_endpoints(manifest)}

    def execute(endpoint_id, payload, context, opts \\ []) do
      Pristine.Runtime.execute(@manifest, endpoint_id, payload, context, opts)
    end
  end
  """
end

defp render_endpoint_fn(%{id: id}) do
  """
    def #{fn_name}(payload, context, opts \\ []) do
      Pristine.Runtime.execute(@manifest, #{inspect(fn_name)}, payload, context, opts)
    end
  """
end
```

**Current output is minimal:**
- One function per endpoint
- Just delegates to runtime
- No typed params, no docstrings, no options extraction

---

## 4. Tinkex Elixir Port (Reference Implementation)

The existing Tinkex port shows how Elixir idiomatically implements similar patterns.

### 4.1 API Module (Client Equivalent)

From `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/api/api.ex` (lines 36-93):

```elixir
def post(path, body, opts) do
  config = Keyword.fetch!(opts, :config)

  query_params = URL.normalize_query_params(Keyword.get(opts, :query))
  url = URL.build_url(config.base_url, path, config.default_query, query_params)
  timeout = Keyword.get(opts, :timeout, config.timeout)
  headers = Headers.build(:post, config, opts, timeout)
  max_retries = Keyword.get(opts, :max_retries, config.max_retries)
  pool_name = PoolKey.resolve_pool_name(config.http_pool, config.base_url, pool_type)

  with {:ok, prepared_headers, prepared_body} <- Request.prepare_body(body, headers, files, transform_opts),
       request <- Finch.build(:post, url, prepared_headers, prepared_body) do
    {result, retry_count, duration} =
      execute_with_telemetry(
        fn -> Retry.execute(request, pool_name, timeout, max_retries, config.dump_headers?) end,
        metadata
      )

    ResponseHandler.handle(result, ...)
  end
end
```

### 4.2 Resource Module Pattern

From `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/api/models.ex` (lines 1-45):

```elixir
defmodule Tinkex.API.Models do
  @moduledoc """
  Model metadata and lifecycle endpoints.
  """

  alias Tinkex.Types.{GetInfoResponse, UnloadModelResponse}

  @spec get_info(map(), keyword()) :: {:ok, GetInfoResponse.t()} | {:error, Tinkex.Error.t()}
  def get_info(request, opts) do
    client = Tinkex.API.client_module(opts)

    case client.post("/api/v1/get_info", request, Keyword.put(opts, :pool_type, :training)) do
      {:ok, json} -> {:ok, GetInfoResponse.from_json(json)}
      {:error, _} = error -> error
    end
  end
end
```

**Pattern:**
1. Module for resource namespace
2. Each function: path + request map + opts
3. Response parsed into typed struct

---

## 5. Gap Analysis

### 5.1 Missing in Pristine Manifest/Endpoint

| Feature | Tinker Has | Pristine Has | Gap |
|---------|-----------|--------------|-----|
| Endpoint path | Yes | Yes | - |
| HTTP method | Yes | Yes | - |
| Request/response types | Yes | Yes (by name) | - |
| Docstrings | Yes (in code) | No | Need `description` field |
| Idempotency header | Yes | No | Need `idempotency_header` field |
| Streaming support | Yes (`stream_cls`) | Yes (`streaming: bool`) | Need stream type |
| Raw response mode | Yes | No | Need `raw_response` option |
| Multipart | Yes | Yes | - |
| Per-endpoint timeout | Yes | Via `opts` | Partial |
| Resource grouping | Yes (class) | No | Need `resource` or `group` field |

### 5.2 Missing in Pristine Codegen

| Feature | Tinker Output | Pristine Output | Gap |
|---------|--------------|-----------------|-----|
| Typed request param | `request: CreateModelRequest` | `payload` (untyped) | Need request type |
| Response type | `-> UntypedAPIFuture` | Untyped | Need return spec |
| Docstring | Yes | No | Generate from description |
| Extra options params | `extra_headers`, `timeout`, etc. | Generic `opts` | Expand options |
| Request serialization | `model_dump(request)` | Serializer adapter | Different approach |
| Error types | Status-specific exceptions | Generic `{:error, term}` | Need error module |
| Resource modules | One class per resource | All in one module | Need resource grouping |

### 5.3 Missing in Pristine Context/Pipeline

| Feature | Tinker | Pristine | Gap |
|---------|--------|----------|-----|
| Credential validation | `api_key.startswith("tml-")` | No | Add to auth adapters |
| Env var fallback | `os.environ.get(...)` | No | Add to context builder |
| Default base URL | Hardcoded default | `nil` | Add default support |
| Idempotency key generation | UUID per request | No | Add to pipeline |
| `x-should-retry` header | Yes | No | Add to retry adapter |
| Response validation | `_strict_response_validation` | No | Add to serializer |

### 5.4 Missing Request Options Pattern

Tinker's `make_request_options`:
```python
def make_request_options(
    *,
    query: Query | None = None,
    extra_headers: Headers | None = None,
    extra_query: Query | None = None,
    extra_body: Body | None = None,
    idempotency_key: str | None = None,
    timeout: float | httpx.Timeout | None | NotGiven = NOT_GIVEN,
    post_parser: PostParser | NotGiven = NOT_GIVEN,
) -> RequestOptions:
```

Pristine's `opts`:
```elixir
opts = [
  headers: %{},
  query: %{},
  path_params: %{}
]
```

**Gap:** No `idempotency_key`, `timeout`, `extra_body`, `post_parser`.

---

## 6. Recommended Changes

### 6.1 Manifest Schema Extensions

```yaml
# Extended endpoint schema
endpoints:
  - id: create_model
    method: POST
    path: /api/v1/create_model
    request: CreateModelRequest
    response: UntypedAPIFuture
    resource: models              # NEW: Resource grouping
    description: |                # NEW: Documentation
      Creates a new model.
      Pass a LoRA config to create a new LoRA adapter.
    idempotency: true             # NEW: Enable idempotency header
    streaming: false
    timeout: 30000                # NEW: Per-endpoint default timeout
    retry: default
```

### 6.2 Codegen Enhancements

**Phase 1: Rich function signatures**
```elixir
# Generated code should look like:
defmodule MyAPI.Models do
  @moduledoc "Model metadata and lifecycle endpoints."

  @doc """
  Creates a new model.

  Pass a LoRA config to create a new LoRA adapter.

  ## Parameters

    * `request` - CreateModelRequest
    * `context` - Runtime context
    * `opts` - Options:
      * `:timeout` - Override timeout (ms)
      * `:idempotency_key` - Custom idempotency key
      * `:extra_headers` - Additional headers
      * `:extra_query` - Additional query params

  ## Returns

    * `{:ok, UntypedAPIFuture.t()}` on success
    * `{:error, Pristine.Error.t()}` on failure
  """
  @spec create_model(map(), Pristine.Core.Context.t(), keyword()) ::
          {:ok, map()} | {:error, Pristine.Error.t()}
  def create_model(request, context, opts \\ []) do
    Pristine.Runtime.execute(
      @manifest,
      "create_model",
      request,
      context,
      opts
    )
  end
end
```

**Phase 2: Resource module generation**
- Group endpoints by `resource` field
- Generate one module per resource
- Generate client module with resource accessors

### 6.3 Pipeline Enhancements

```elixir
# Add to Context
defstruct [
  # ... existing fields ...
  idempotency_header: "X-Idempotency-Key",
  default_timeout: 60_000,
  strict_response_validation: false
]

# Add to Pipeline.execute/5
defp maybe_add_idempotency(request, endpoint, context, opts) do
  if endpoint.idempotency do
    key = Keyword.get(opts, :idempotency_key) || generate_idempotency_key()
    header = context.idempotency_header
    put_in(request.headers[header], key)
  else
    request
  end
end
```

### 6.4 Error Module

```elixir
defmodule Pristine.Error do
  defstruct [:message, :type, :status, :body, :response]

  @type t :: %__MODULE__{
    message: String.t(),
    type: :bad_request | :authentication | :permission_denied | :not_found |
          :conflict | :unprocessable_entity | :rate_limit | :internal_server | :unknown,
    status: integer() | nil,
    body: term(),
    response: Pristine.Core.Response.t() | nil
  }

  def from_response(%{status: 400} = resp), do: %__MODULE__{type: :bad_request, ...}
  def from_response(%{status: 401} = resp), do: %__MODULE__{type: :authentication, ...}
  # ... etc
end
```

---

## 7. Concrete Next Steps (TDD Approach)

### Priority 1: Manifest Schema Extension (Week 1)

1. **Test:** Write tests for `Pristine.Manifest.load/1` with new fields
   - `resource` field parsing
   - `description` field parsing
   - `idempotency` boolean
   - Per-endpoint `timeout`

2. **Implement:** Extend `Pristine.Manifest.Endpoint` struct
   ```elixir
   # lib/pristine/manifest/endpoint.ex
   defstruct [
     # existing...
     resource: nil,           # NEW
     description: nil,        # NEW
     idempotency: false,      # NEW
     timeout: nil             # NEW (endpoint-level override)
   ]
   ```

3. **Test:** Manifest validation rejects invalid values

### Priority 2: Enhanced Codegen (Week 2)

1. **Test:** Write tests for `Pristine.Codegen.Elixir.render_client_module/2`
   - Generates @doc from description
   - Generates @spec with request/response types
   - Groups functions by resource

2. **Implement:** Update `render_endpoint_fn/1`
   ```elixir
   defp render_endpoint_fn(%{id: id, description: desc, request: req_type, response: resp_type}) do
     """
       @doc \"\"\"
       #{desc}
       \"\"\"
       @spec #{fn_name}(map(), Context.t(), keyword()) :: {:ok, term()} | {:error, term()}
       def #{fn_name}(request, context, opts \\\\ []) do
         Pristine.Runtime.execute(@manifest, #{inspect(id)}, request, context, opts)
       end
     """
   end
   ```

3. **Test:** Resource module generation (new function)
   ```elixir
   def render_resource_modules(namespace, manifest) do
     manifest.endpoints
     |> Enum.group_by(& &1.resource)
     |> Enum.map(fn {resource, endpoints} ->
       render_resource_module(namespace, resource, endpoints)
     end)
   end
   ```

### Priority 3: Idempotency Support (Week 3)

1. **Test:** Pipeline adds idempotency header when `endpoint.idempotency == true`
2. **Test:** Custom key from `opts[:idempotency_key]` takes precedence
3. **Implement:** Add `maybe_add_idempotency/4` to pipeline

### Priority 4: Error Types (Week 3-4)

1. **Test:** `Pristine.Error.from_response/1` maps status codes
2. **Test:** Pipeline wraps transport errors in `Pristine.Error`
3. **Implement:** Error module and pipeline integration

### Priority 5: Options Expansion (Week 4)

1. **Test:** `opts[:timeout]` overrides context default
2. **Test:** `opts[:extra_headers]` merged into request
3. **Test:** `opts[:extra_query]` merged into URL
4. **Implement:** Update `Pipeline.build_request/5`

---

## 8. File Reference Summary

### Tinker Python SDK

| File | Key Patterns |
|------|-------------|
| `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/_client.py` | Client init, resource accessors, auth headers |
| `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/_base_client.py` | HTTP methods, request building, retry, response processing |
| `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/_resource.py` | Base resource class, method aliases |
| `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/resources/models.py` | Resource methods, request options, docstrings |
| `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/resources/sampling.py` | Same pattern |
| `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/resources/training.py` | Same pattern |
| `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/resources/weights.py` | Path params, DELETE method |
| `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/resources/futures.py` | Raw response wrapper |
| `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/resources/service.py` | GET methods, no body |

### Pristine Elixir

| File | Key Patterns |
|------|-------------|
| `/home/home/p/g/n/pristine/lib/pristine/manifest.ex` | Manifest loading, validation |
| `/home/home/p/g/n/pristine/lib/pristine/manifest/endpoint.ex` | Endpoint struct |
| `/home/home/p/g/n/pristine/lib/pristine/core/context.ex` | Runtime context |
| `/home/home/p/g/n/pristine/lib/pristine/core/pipeline.ex` | Request execution |
| `/home/home/p/g/n/pristine/lib/pristine/runtime.ex` | Runtime entrypoint |
| `/home/home/p/g/n/pristine/lib/pristine/codegen.ex` | Codegen orchestration |
| `/home/home/p/g/n/pristine/lib/pristine/codegen/elixir.ex` | Elixir renderer |
| `/home/home/p/g/n/pristine/lib/pristine/core/headers.ex` | Header building |
| `/home/home/p/g/n/pristine/lib/pristine/core/url.ex` | URL building |
| `/home/home/p/g/n/pristine/lib/pristine/adapters/transport/finch.ex` | HTTP transport |

### Tinkex Elixir (Reference)

| File | Key Patterns |
|------|-------------|
| `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/api/api.ex` | HTTP client, telemetry |
| `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/api/rest.ex` | REST endpoints |
| `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/api/models.ex` | Resource module |
| `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/api/service.ex` | Resource module |

---

## 9. Conclusion

The Tinker Python SDK provides a rich, type-safe, developer-friendly interface through:
1. Lazy resource namespacing
2. Typed request/response parameters
3. Comprehensive docstrings
4. Flexible request options (timeout, idempotency, extra headers)
5. Status-specific error types

Pristine's manifest-driven approach has a solid foundation with:
1. Declarative endpoint definitions
2. Pluggable adapters (transport, serializer, retry, circuit breaker)
3. Clean pipeline composition

To match Tinker's ergonomics, Pristine needs:
1. Extended manifest schema (resource grouping, descriptions, idempotency)
2. Enhanced codegen (docstrings, specs, resource modules)
3. Idempotency key generation in pipeline
4. Structured error types

The recommended changes maintain Pristine's manifest-first philosophy while generating code that provides the same developer experience as a hand-crafted SDK.
