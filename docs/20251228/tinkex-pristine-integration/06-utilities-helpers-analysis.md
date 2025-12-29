# Tinker Python SDK Utilities & Helpers Analysis

## 1. File Upload Handling and Multipart Encoding

**Location**: `/tinker/src/tinker/_files.py`

### Key Functions

**`to_httpx_files(files: RequestFiles | None) -> HttpxRequestFiles | None`**
- Converts SDK file format to httpx-compatible format
- Handles both mapping (dict) and sequence (list of tuples) file inputs
- Uses internal `_transform_file()` to normalize file representations

**`_transform_file(file: FileTypes) -> HttpxFileTypes`**
- Converts PathLike objects to (filename, bytes) tuples
- Handles raw file tuples: extracts and reads content
- Reads file bytes from Path objects using `pathlib.Path(file).read_bytes()`

**`read_file_content(file: FileContent) -> HttpxFileContent`**
- Converts PathLike to bytes via `pathlib.Path(file).read_bytes()`
- Passes through bytes, io.IOBase, and tuples as-is

**Async Variants**:
- `async_to_httpx_files()` and `_async_transform_file()`
- Uses `anyio.Path` for non-blocking I/O

**Type Guards**:
- `is_base64_file_input(obj)`: Checks for `io.IOBase` or `os.PathLike`
- `is_file_content(obj)`: Validates bytes, tuple, io.IOBase, or PathLike types
- `assert_is_file_content(obj, *, key=None)`: Raises RuntimeError on invalid

---

## 2. Query String Serialization

**Location**: `/tinker/src/tinker/_qs.py`

### Core Class: `Querystring`

**Configuration Options**:
```python
array_format: Literal["comma", "repeat", "indices", "brackets"]
nested_format: Literal["dots", "brackets"]
```

**Key Methods**:
- `stringify(params, *, array_format=..., nested_format=...)`: Encode params to query string
- `parse(query_string)`: Parse query string back to dict (inverse of stringify)

### Array Format Handling

| Format | Example Output |
|--------|----------------|
| `"comma"` | `key=val1,val2,val3` |
| `"repeat"` | `key=val1&key=val2&key=val3` |
| `"brackets"` | `key[]=val1&key[]=val2` |
| `"indices"` | NOT YET IMPLEMENTED |

### Nested Format Handling

| Format | Example Output |
|--------|----------------|
| `"dots"` | `parent.child=value` |
| `"brackets"` | `parent[child]=value` |

### Primitive Value Conversion
```python
True  -> "true"
False -> "false"
None  -> "" (filtered out)
else  -> str(value)
```

**Default Configuration**:
- `array_format="repeat"`
- `nested_format="brackets"`

---

## 3. Compatibility Helpers

**Location**: `/tinker/src/tinker/_compat.py`

### Pydantic Version Detection
```python
PYDANTIC_V2 = pydantic.VERSION.startswith("2.")
```

### Version-Agnostic APIs

| Function | v1 API | v2 API |
|----------|--------|--------|
| `parse_obj` | `model.parse_obj(value)` | `model.model_validate(value)` |
| `field_is_required` | `field.required` | `field.is_required()` |
| `field_get_default` | `field.get_default()` | + PydanticUndefined check |
| `field_outer_type` | `field.outer_type_` | `field.annotation` |
| `get_model_config` | `model.__config__` | `model.model_config` |
| `get_model_fields` | `model.__fields__` | `model.model_fields` |
| `model_copy` | `model.copy(deep=)` | `model.model_copy(deep=)` |
| `model_json` | `model.json(indent=)` | `model.model_dump_json(indent=)` |
| `model_dump` | `model.dict(...)` | `model.model_dump(mode=, ...)` |
| `model_parse` | `model.parse_obj(data)` | `model.model_validate(data)` |

### Generic Model Support
- v2: Simple `pydantic.BaseModel` inheritance
- v1: Inherits from `pydantic.generics.GenericModel`

---

## 4. SDK Constants and Configuration

**Location**: `/tinker/src/tinker/_constants.py`

```python
# Header Names
RAW_RESPONSE_HEADER = "X-Stainless-Raw-Response"
OVERRIDE_CAST_TO_HEADER = "____stainless_override_cast_to"

# Timeout Configuration
DEFAULT_TIMEOUT = httpx.Timeout(timeout=60, connect=5.0)

# Retry Configuration
DEFAULT_MAX_RETRIES = 10
INITIAL_RETRY_DELAY = 0.5  # seconds
MAX_RETRY_DELAY = 10.0     # seconds

# Connection Pooling
DEFAULT_CONNECTION_LIMITS = httpx.Limits(
    max_connections=1000,
    max_keepalive_connections=20
)
```

---

## 5. Utility Functions

**Location**: `/tinker/src/tinker/_utils/_utils.py`

### Core Type Guards
```python
is_dict(obj) -> TypeGuard[dict]
is_list(obj) -> TypeGuard[list]
is_tuple(obj) -> TypeGuard[tuple[object, ...]]
is_mapping(obj) -> TypeGuard[Mapping]
is_sequence(obj) -> TypeGuard[Sequence]
is_iterable(obj) -> TypeGuard[Iterable]
is_given(obj) -> TypeGuard[_T]  # Tests if NOT NotGiven
```

### Data Processing

**`flatten(t: Iterable[Iterable[_T]]) -> list[_T]`**
- Flattens 2D iterables into 1D list

**`extract_files(query, *, paths) -> list[tuple[str, FileTypes]]`**
- Recursively extracts files from nested dict structures
- Paths use special `'<array>'` marker for array traversal
- MUTATES the input dictionary

**`deepcopy_minimal(item: _T) -> _T`**
- Performance-optimized deepcopy for dicts and lists only

**`strip_not_given(obj) -> object`**
- Removes all keys with `NotGiven` values from mappings

### String Utilities
- `removeprefix(string, prefix)` - Python 3.8 compatible
- `removesuffix(string, suffix)` - Python 3.8 compatible
- `file_from_path(path)` - Returns `(basename, read_bytes())`

### Type Coercion
```python
coerce_integer(val: str) -> int
coerce_float(val: str) -> float
coerce_boolean(val: str) -> bool  # "true", "1", "on" -> True
maybe_coerce_* variants accept str | None
```

### JSON Safety
**`json_safe(data: object) -> object`**
- Recursively converts datetime -> isoformat()
- Converts iterables to lists

---

## 6. Data Transformation and Property Mapping

**Location**: `/tinker/src/tinker/_utils/_transform.py`

### PropertyInfo Class
```python
class PropertyInfo:
    alias: str | None           # Field name remapping
    format: PropertyFormat | None  # "iso8601", "base64", "custom"
    format_template: str | None  # strftime template
    discriminator: str | None   # For polymorphic types
```

### Transformation Functions

**`transform(data: _T, expected_type: object) -> _T`**
- Recursively transforms dicts based on type annotations
- Example: `{"card_id": "123"}` -> `{"cardID": "123"}` (with alias)
- Handles TypedDict, Mapping, List, Iterable, Union types
- Converts Pydantic models to dicts (mode="json")

**`maybe_transform(data, expected_type) -> Any | None`**
- Wrapper allowing `None` input

**Async variants**: `async_transform()`, `async_maybe_transform()`

### Format Handling
```python
"iso8601" -> date/datetime.isoformat()
"base64"  -> base64.b64encode(file_bytes).decode("ascii")
"custom"  -> date.strftime(format_template)
```

---

## 7. Additional Utility Modules

### Proxy Pattern (`_utils/_proxy.py`)
```python
class LazyProxy(Generic[T], ABC):
    """Lazy-loads resources on first access"""
    def __load__(self) -> T: ...
```

### Type Checking (`_utils/_typing.py`)
```python
is_annotated_type()
is_list_type()
is_iterable_type()
is_union_type()
is_required_type()
is_typevar()
strip_annotated_type()
extract_type_arg()
```

### Async/Sync Conversion (`_utils/_sync.py`)
```python
asyncify(function) -> async wrapper
to_thread(func, *args, **kwargs) -> Awaitable[T]
```

### Stream Consumption (`_utils/_streams.py`)
```python
consume_sync_iterator(iterator) -> None
consume_async_iterator(async_iterator) -> None
```

### Logging (`_utils/_logs.py`)
```python
logger = logging.getLogger("tinker")
setup_logging()  # Respects TINKER_LOG env var
```

### Reflection (`_utils/_reflection.py`)
```python
function_has_argument(func, arg_name) -> bool
assert_signatures_in_sync(source_func, check_func) -> None
```

---

## 8. Critical Patterns for Pristine Port

1. **File Handling**: Both sync and async variants required
2. **Query Strings**: Array/nested format flexibility essential
3. **Pydantic Compatibility**: Abstract v1/v2 differences completely
4. **Property Aliases**: Transform TypedDicts using Annotated metadata
5. **Type Coercion**: Support string-to-type conversions
6. **NotGiven Pattern**: Special sentinel type for optional parameters
7. **Lazy Imports**: Use proxies to defer module initialization
8. **Async Everywhere**: Parallel sync/async implementations required

---

*Document created: 2025-12-28*
*Source: Agent analysis of Tinker Python SDK utility modules*
