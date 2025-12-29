# Client Architecture Analysis for Tinker Python SDK

## 1. BASE CLIENT STRUCTURE (_base_client.py)

### Architecture Overview
The `BaseClient` is a generic class parameterized by HTTP client type and stream type that serves as the foundation for all API clients. It implements:

- URL normalization and management
- Request/response lifecycle
- Retry logic with exponential backoff
- Header building and validation
- Response parsing and type coercion
- Pagination support
- Platform-specific telemetry headers

### Key Components:

**BaseClient Class Hierarchy:**
```
BaseClient[_HttpxClientT, _DefaultStreamT] (Generic)
    └── AsyncAPIClient extends BaseClient[httpx.AsyncClient, AsyncStream[Any]]
```

> Note: The Tinker SDK is async-only. No SyncAPIClient exists.

**Critical Configuration:**
- `_version`: SDK version for user agent
- `_base_url`: Normalized URL with trailing slash enforcement
- `max_retries`: Retry policy (defaults to `DEFAULT_MAX_RETRIES = 10`)
- `timeout`: Request timeout (defaults to `DEFAULT_TIMEOUT = httpx.Timeout(timeout=60, connect=5.0)`)
- `_strict_response_validation`: Flag for strict Pydantic validation
- `_idempotency_header`: Optional idempotency key header name
- `_custom_headers`: Injected headers for all requests
- `_custom_query`: Injected query params for all requests

### URL Management:
```python
def _enforce_trailing_slash(self, url: URL) -> URL
def _prepare_url(self, url: str) -> URL  # Merges relative URLs with base_url
```

### Default Headers Property:
The client automatically injects platform and version headers:
```python
{
    "Accept": "application/json",
    "Content-Type": "application/json",
    "User-Agent": self.user_agent,  # AsyncTinker/Python x.y.z
    **self.platform_headers(),      # X-Stainless-* headers
    **self.auth_headers,            # Custom auth headers
    **self._custom_headers,
}
```

---

## 2. ASYNC CLIENT IMPLEMENTATION (_client.py)

### AsyncTinker Class Structure
`AsyncTinker` extends `AsyncAPIClient` and adds:

**Initialization:**
- API key validation (must start with "tml-" prefix)
- Environment variable fallback: `TINKER_API_KEY`, `TINKER_BASE_URL`
- Default base URL: `https://tinker.thinkingmachines.dev/services/tinker-prod`
- Idempotency header set to: `X-Idempotency-Key`

**Resource Attachment Pattern:**
Uses `@cached_property` decorators to lazily attach resources:
```python
@cached_property
def service(self) -> AsyncServiceResource:
    from .resources.service import AsyncServiceResource
    return AsyncServiceResource(self)
```

Resources include: service, training, models, weights, sampling, futures, telemetry

**Response Mode Wrappers:**
- `with_raw_response`: Returns raw `AsyncAPIResponse` objects
- `with_streaming_response`: Returns context managers for streaming responses

**Query String Format:**
Overrides parent to use comma-separated arrays: `Querystring(array_format="comma")`

**Authentication:**
```python
@property
def auth_headers(self) -> dict[str, str]:
    return {"X-API-Key": self.api_key}
```

**Telemetry Headers:**
Adds `X-Stainless-Async` header indicating async runtime library

### Copy/Clone Pattern:
```python
def copy(self, *, api_key=None, base_url=None, ...) -> Self
def with_options(self, ...) -> Self  # Alias for copy()
```

Supports partial overrides while preserving existing configuration.

---

## 3. RESOURCE ATTACHMENT (_resource.py)

### AsyncAPIResource Base Class
Minimal but crucial pattern for all resources:

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

    async def _sleep(self, seconds: float) -> None:
        await anyio.sleep(seconds)
```

**Key Pattern:**
- Resources receive the client instance
- Methods are bound directly from client (`self._get = client.get`)
- Provides a unified interface for all HTTP operations
- Single async sleep utility for delays between requests

---

## 4. REQUEST/RESPONSE LIFECYCLE

### Request Building (_build_request)
Steps:
1. Merge JSON data with extra_json (regardless of content type)
2. Build headers using `_build_headers()`
3. Merge default query params with request params
4. Handle multipart/form-data content-type header removal (let httpx generate it)
5. Convert files to httpx format
6. Handle SNI hostname overrides for hostnames with underscores
7. Construct httpx.Request via `self._client.build_request()`

**Special Handling:**
- Multipart form data boundary generation delegated to httpx
- GET requests strip body and Content-Type header
- Query string encoding via custom `Querystring()` class with configurable array format

### Request Execution (async request method)
Main retry loop in `AsyncAPIClient.request()`:

```
1. Override cast_to if header-based override is present
2. Copy options to preserve original for retries
3. Generate idempotency key for non-GET requests
4. Loop up to max_retries + 1 times:
   a. Prepare options via _prepare_options hook
   b. Build request
   c. Call _prepare_request hook
   d. Apply custom auth if needed
   e. Send request via httpx.AsyncClient.send()
   f. Handle exceptions:
      - httpx.TimeoutException -> APITimeoutError
      - Other exceptions -> APIConnectionError
   g. Validate status code, retry on 408/409/429/5xx or x-should-retry header
   h. Process response via _process_response()
```

**Retry Mechanism:**
- Exponential backoff: `min(INITIAL_RETRY_DELAY * pow(2.0, nb_retries), MAX_RETRY_DELAY)`
- Jitter: `1 - 0.25 * random()`
- Respects `Retry-After` header (milliseconds and seconds)
- Caps retry count to 1000 to prevent overflow
- Idempotency key reused across retries

### Response Processing (_process_response)
Returns response based on cast_to type:
1. Check if cast_to is custom BaseAPIResponse subclass
2. If not, wrap in AsyncAPIResponse
3. Check for raw response header
4. Call `api_response.parse()` if not raw

---

## 5. AUTHENTICATION HANDLING

### API Key Authentication
```python
# In AsyncTinker.__init__:
self.api_key = api_key
# In auth_headers property:
return {"X-API-Key": self.api_key}
```

### Custom Auth Support
BaseClient provides hook point:
```python
@property
def custom_auth(self) -> httpx.Auth | None:
    return None  # Override for Bearer tokens, OAuth, etc.
```

### Idempotency Keys
- Optional `X-Idempotency-Key` header (configured per client)
- Auto-generated via `_idempotency_key()`: `f"stainless-python-retry-{uuid.uuid4()}"`
- Reused across retries for same request
- Only applied to non-GET requests

---

## 6. RETRY AND RESILIENCE PATTERNS

### Retry Decision Logic (_should_retry)
```python
def _should_retry(self, response: httpx.Response) -> bool:
    # 1. Check x-should-retry header (explicit control)
    # 2. Retry on 408 (Request Timeout)
    # 3. Retry on 409 (Conflict/Lock Timeout)
    # 4. Retry on 429 (Rate Limit)
    # 5. Retry on 5xx (Server Errors)
    # 6. Don't retry otherwise
```

### Timeout Calculation
```python
def _calculate_retry_timeout(self, remaining_retries, options, response_headers):
    max_retries = options.get_max_retries(self.max_retries)

    # 1. Use Retry-After header if 0 < value <= 60 seconds
    # 2. Apply exponential backoff: 2^retries * INITIAL_DELAY
    # 3. Cap at MAX_RETRY_DELAY
    # 4. Apply jitter: multiply by (1 - 0.25 * random())
```

### Error Handling
Maps HTTP status codes to specific exception types:
- 400 -> BadRequestError
- 401 -> AuthenticationError
- 403 -> PermissionDeniedError
- 404 -> NotFoundError
- 409 -> ConflictError
- 422 -> UnprocessableEntityError
- 429 -> RateLimitError
- 5xx -> InternalServerError

---

## 7. RESPONSE HANDLING (_response.py)

### BaseAPIResponse Class
Generic response wrapper with:
```python
class BaseAPIResponse(Generic[R]):
    _cast_to: type[R]
    _client: BaseClient
    _parsed_by_type: dict[type, Any]  # Cache for multiple parses
    _is_sse_stream: bool
    _stream_cls: type[Stream | AsyncStream] | None
    _options: FinalRequestOptions
    http_response: httpx.Response
    retries_taken: int
```

### Response Parsing (_parse method)
Supports multiple types:
1. **SSE Streams**: Auto-wraps in Stream/AsyncStream
2. **Primitive Types**: str, bytes, int, float, bool (direct conversion)
3. **httpx.Response**: Pass-through
4. **BaseModel**: Pydantic validation via `validate_type()` or `construct_type()`
5. **dict/list**: JSON parsing
6. **Union types**: Handled by Pydantic

### Content-Type Handling
- JSON (application/json): Parse as JSON
- Non-JSON: Return raw text
- Fallback: Attempt JSON parsing for BaseModels

### Caching
Responses cache parsed values by type:
```python
cache_key = to if to is not None else self._cast_to
cached = self._parsed_by_type.get(cache_key)
if cached is not None:
    return cached
```

### Async APIResponse Methods
- `async parse()`: Parse and cache response
- `async read()`: Read entire response body
- `async text()`: Get text representation
- `async json()`: Get JSON representation
- `async close()`: Release connection
- `async iter_bytes()`: Stream chunks
- `async iter_text()`: Stream text chunks
- `async iter_lines()`: Stream lines

### Binary Response Support
Special classes for binary data:
- `AsyncBinaryAPIResponse`: Helper for binary responses
- `AsyncStreamedBinaryAPIResponse`: Stream binary to file

---

## 8. CUSTOM HTTP BEHAVIORS

### Header Customization
Headers built in this order:
1. Default headers (Accept, Content-Type, User-Agent)
2. Platform headers (X-Stainless-* telemetry)
3. Auth headers (X-API-Key)
4. Custom headers (client-level)
5. Request-level headers (override previous)

### Telemetry Headers
Automatically injected:
```python
{
    "X-Stainless-Package-Version": version,
    "X-Stainless-OS": platform,  # MacOS, Linux, Windows, etc.
    "X-Stainless-Arch": architecture,  # x64, arm64, etc.
    "X-Stainless-Runtime": runtime,  # CPython, PyPy, etc.
    "X-Stainless-Runtime-Version": version,  # 3.11.0, etc.
}
```

### Retry Telemetry
```python
{
    "x-stainless-retry-count": str(retries_taken),
    "x-stainless-read-timeout": str(timeout),
}
```

### Raw Response Control
Uses internal headers to control response behavior:
- `X-Stainless-Raw-Response: raw` -> Return AsyncAPIResponse wrapper
- `X-Stainless-Raw-Response: stream` -> Stream response body
- `____stainless_override_cast_to: CustomClass` -> Override response type

### Request Options Hook
`async _prepare_options(options: FinalRequestOptions) -> FinalRequestOptions`
- Override point for mutating options before building request
- Allows subclasses to inject custom logic

### Request Hook
`async _prepare_request(request: httpx.Request) -> None`
- Called after request construction
- Useful for signing requests or final header tweaks

### Query String Formatting
`Querystring` class supports configurable array formats:
- Default: Standard array encoding
- Tinker override: `array_format="comma"` for comma-separated values

### Pagination Support
Built-in async pagination:
```python
class AsyncPaginator(Generic[_T, AsyncPageT]):
    async def _get_page() -> AsyncPageT
    async def __aiter__() -> AsyncIterator[_T]
```

Pages implement:
- `has_next_page()`: Check if more pages exist
- `next_page_info()`: Get params for next page
- `async get_next_page()`: Fetch next page
- `async iter_pages()`: Iterate through all pages
- `async __aiter__()`: Iterate through all items across pages

---

## 9. EXCEPTION HANDLING (_exceptions.py)

### Exception Hierarchy
```
Exception
├── TinkerError
    ├── APIError
    │   ├── APIResponseValidationError
    │   ├── APIStatusError
    │   │   ├── BadRequestError (400)
    │   │   ├── AuthenticationError (401)
    │   │   ├── PermissionDeniedError (403)
    │   │   ├── NotFoundError (404)
    │   │   ├── ConflictError (409)
    │   │   ├── UnprocessableEntityError (422)
    │   │   ├── RateLimitError (429)
    │   │   └── InternalServerError (5xx)
    │   └── APIConnectionError
    │       └── APITimeoutError
    └── RequestFailedError
```

### Error Properties
All API errors include:
- `message`: Human-readable error message
- `request`: Original httpx.Request
- `body`: Response body (JSON if valid, raw text otherwise)
- `response`: httpx.Response object (for status errors)
- `status_code`: HTTP status code

---

## 10. KEY DESIGN PATTERNS FOR ELIXIR PORTING

### Patterns to Replicate:

1. **Generic Base Client**: Use type parameters/protocols for HTTP transport
2. **Async-First Design**: All operations are naturally async (handle both async/await patterns)
3. **Lazy Resource Loading**: Use module attributes for resource instantiation
4. **Cached Properties**: Cache expensive operations like platform detection
5. **Hook Points**: Provide `_prepare_options` and `_prepare_request` for customization
6. **Telemetry Headers**: Auto-inject platform/version information
7. **Intelligent Retries**: Exponential backoff with jitter and Retry-After parsing
8. **Multi-Type Response Parsing**: Support multiple parse strategies based on content-type
9. **Stream Support**: Native streaming with optional buffering
10. **Pagination Abstractions**: Stateful pagination with async iterators
11. **Custom Header Control**: Internal headers for controlling SDK behavior
12. **Error Mapping**: Status codes map to specific exception types
13. **Copy/Clone Pattern**: Client cloning with partial overrides
14. **Idempotency Keys**: Auto-generated and reused across retries

---

*Document created: 2025-12-28*
*Source: Agent analysis of Tinker Python SDK*
