# Tinker Python SDK Type System - Comprehensive Analysis

## Executive Summary

The Tinker SDK implements a sophisticated type system built on Pydantic (v1 and v2 compatible) with support for:
- Discriminated unions with `Annotated[Union[...], PropertyInfo(discriminator="field")]`
- Custom type coercion and validators
- Serialization/deserialization patterns
- Request/response model hierarchies
- Enum-based discriminators
- Optional fields with smart defaults

---

## 1. Core Type System Architecture

### 1.1 Base Classes (_models.py)

**StrictBase**: For request types
- `frozen=True`: Immutable once created
- `extra="forbid"`: Rejects unknown fields (catches user errors early)
- Parent for all request models

**BaseModel**: For response types
- `frozen=True`: Immutable
- `extra="ignore"`: Allows unknown fields (forward-compatible with API changes)
- Parent for all response models
- Provides graceful degradation when server adds new fields

**GenericModel**: For generic parameterized types
- Supports `Generic[T]` inheritance
- Pydantic v1/v2 compatible wrapper

### 1.2 Type Handling Patterns (_types.py)

**NotGiven Sentinel**:
- Distinguishes omitted kwargs from `None` values
- Essential for optional request parameters
- Used in: `Union[value, NotGiven]`

> **Sinter Note**: Sinter already supports the NotGiven pattern. Generated code
> should use `Sinter.NotGiven` for optional parameters that distinguish between
> "not provided" and "explicitly set to nil".

**Type Aliases**:
```python
ModelID: TypeAlias = str
Severity: TypeAlias = Literal["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"]
TensorDtype: TypeAlias = Literal["int64", "float32"]
LossFnType: TypeAlias = Literal["cross_entropy", "importance_sampling", "ppo", "cispo", "dro"]
StopReason: TypeAlias = Literal["length", "stop"]
EventType: TypeAlias = Literal["SESSION_START", "SESSION_END", "UNHANDLED_EXCEPTION", "GENERIC_EVENT"]
CheckpointType = Literal["training", "sampler"]
```

---

## 2. Discriminated Union Pattern

### 2.1 How It Works

**Example from ModelInputChunk**:
```python
ModelInputChunk: TypeAlias = Annotated[
    Union[EncodedTextChunk, ImageAssetPointerChunk, ImageChunk],
    PropertyInfo(discriminator="type")
]
```

**Variant Types**:
```python
class EncodedTextChunk(StrictBase):
    tokens: Sequence[int]
    type: Literal["encoded_text"] = "encoded_text"

class ImageChunk(StrictBase):
    data: bytes
    format: Literal["png", "jpeg"]
    type: Literal["image"] = "image"

class ImageAssetPointerChunk(StrictBase):
    location: str
    format: Literal["png", "jpeg"]
    type: Literal["image_asset_pointer"] = "image_asset_pointer"
```

**Key Patterns**:
- Discriminator field contains literal type value
- Field is required and has default matching class name variant
- Union resolved at runtime via discriminator field
- PropertyInfo metadata enables smart deserialization

### 2.2 Union Resolution Strategy (_models.py - construct_type)

1. Validates against union type first
2. If fails, inspects discriminator field in data
3. Finds matching variant by discriminator value
4. Constructs appropriate variant type
5. Falls back to trying each variant in order

### 2.3 Simple Unions (No Discriminator)

**Example from TelemetryEvent**:
```python
TelemetryEvent: TypeAlias = Union[
    SessionStartEvent, SessionEndEvent, UnhandledExceptionEvent, GenericEvent
]
```
- No discriminator annotation
- Tried sequentially until one validates
- Risk: might match wrong variant if schemas overlap

---

## 3. Field Patterns and Validators

### 3.1 Optional Fields

All use `Optional[T] = None`:
```python
class Checkpoint(BaseModel):
    size_bytes: int | None = None
    public: bool = False

class LoraConfig(StrictBase):
    seed: Optional[int] = None
    train_unembed: bool = True
    train_mlp: bool = True
    train_attn: bool = True
```

### 3.2 Custom Validators

**field_validator (Pydantic v2)**:
```python
class ImageChunk(StrictBase):
    data: bytes

    @field_validator("data", mode="before")
    @classmethod
    def validate_data(cls, value: Union[bytes, str]) -> bytes:
        """Deserialize base64 string to bytes if needed."""
        if isinstance(value, str):
            return base64.b64decode(value)
        return value
```

**field_serializer (Pydantic v2)**:
```python
    @field_serializer("data")
    def serialize_data(self, value: bytes) -> str:
        """Serialize bytes to base64 string for JSON."""
        return base64.b64encode(value).decode("utf-8")
```

**model_validator (Pydantic v2)**:
```python
class Datum(StrictBase):
    @model_validator(mode="before")
    @classmethod
    def convert_tensors(cls, data: Any) -> Any:
        """Convert torch.Tensor and numpy arrays to TensorData"""
        if isinstance(data, dict) and "loss_fn_inputs" in data:
            loss_fn_inputs = data["loss_fn_inputs"]
            if isinstance(loss_fn_inputs, dict):
                converted_inputs = {}
                for key, value in loss_fn_inputs.items():
                    converted_inputs[key] = cls._maybe_convert_array(key, value)
                data = dict(data)
                data["loss_fn_inputs"] = converted_inputs
        return data
```

### 3.3 Type Coercion in Validators

**Numpy/PyTorch Integration**:
```python
class TensorData(StrictBase):
    data: Union[List[int], List[float]]
    dtype: TensorDtype
    shape: Optional[List[int]] = None

    @classmethod
    def from_numpy(cls, array: npt.NDArray[Any]) -> "TensorData":
        return cls(
            data=array.flatten().tolist(),
            dtype=_convert_numpy_dtype_to_tensor(array.dtype),
            shape=list(array.shape),
        )

    @classmethod
    def from_torch(cls, tensor: "torch.Tensor") -> "TensorData":
        return cls(
            data=tensor.flatten().tolist(),
            dtype=_convert_torch_dtype_to_tensor(tensor.dtype),
            shape=list(tensor.shape),
        )
```

**String to Enum Base64**:
```python
@field_validator("data", mode="before")
@classmethod
def validate_data(cls, value: Union[bytes, str]) -> bytes:
    if isinstance(value, str):
        return base64.b64decode(value)
    return value
```

---

## 4. Request Types

### 4.1 Base Pattern
```python
class CreateModelRequest(StrictBase):
    session_id: str
    model_seq_id: int
    base_model: str
    user_metadata: Optional[dict[str, Any]] = None
    lora_config: Optional[LoraConfig] = None
    type: Literal["create_model"] = "create_model"

    if PYDANTIC_V2:
        model_config = ConfigDict(protected_namespaces=tuple())
```

**Characteristics**:
- Extends `StrictBase` (forbid extra fields)
- Includes `type: Literal[...]` discriminator
- Protected namespace config for `model_*` fields
- All fields required except those with defaults

### 4.2 Request with Nested Models
```python
class ForwardBackwardInput(StrictBase):
    data: List[Datum]
    loss_fn: LossFnType
    loss_fn_config: Optional[Dict[str, float]] = None

class SampleRequest(StrictBase):
    num_samples: int = 1
    prompt: ModelInput
    sampling_params: SamplingParams
    base_model: Optional[str] = None
    model_path: Optional[str] = None
    sampling_session_id: Optional[str] = None
    seq_id: Optional[int] = None
    prompt_logprobs: Optional[bool] = None
    topk_prompt_logprobs: int = 0
    type: Literal["sample"] = "sample"
```

### 4.3 Protected Namespace Configuration

```python
if PYDANTIC_V2:
    model_config = ConfigDict(protected_namespaces=tuple())
```

**Purpose**: Allow fields like `model_id`, `model_name`, `model_path` without Pydantic warnings about `model_` prefix being reserved for model methods.

---

## 5. Response Types

### 5.1 Base Pattern
```python
class BaseModel(pydantic.BaseModel):
    model_config = ConfigDict(frozen=True, extra="ignore")

class SampledSequence(BaseModel):
    stop_reason: StopReason
    tokens: List[int]
    logprobs: Optional[List[float]] = None

class SampleResponse(BaseModel):
    sequences: Sequence[SampledSequence]
    type: Literal["sample"] = "sample"
    prompt_logprobs: Optional[List[Optional[float]]] = None
    topk_prompt_logprobs: Optional[list[Optional[list[tuple[int, float]]]]] = None
```

**Characteristics**:
- Extend `BaseModel` (ignore extra fields)
- Frozen (immutable)
- May have nested types
- Optional fields with `None` defaults

### 5.2 Nested Response Structures
```python
class GetInfoResponse(BaseModel):
    type: Optional[Literal["get_info"]] = None
    model_data: ModelData
    model_id: ModelID
    is_lora: Optional[bool] = None
    lora_rank: Optional[int] = None
    model_name: Optional[str] = None

class ModelData(BaseModel):
    arch: Optional[str] = None
    model_name: Optional[str] = None
    tokenizer_id: Optional[str] = None
```

### 5.3 Pagination Support
```python
class Cursor(BaseModel):
    offset: int
    limit: int
    total_count: int

class ListSessionsResponse(BaseModel):
    sessions: List[str]
```

---

## 6. Enumeration Patterns

### 6.1 Literal Type Aliases (Most Common)
```python
Severity: TypeAlias = Literal["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"]
StopReason: TypeAlias = Literal["length", "stop"]
CheckpointType = Literal["training", "sampler"]
```

**Advantages**:
- Zero runtime overhead
- Full type checker support
- Easy JSON serialization
- No class instantiation needed

### 6.2 String Enums (When Needed)
```python
class RequestErrorCategory(StrEnum):
    Unknown = auto()
    Server = auto()
    User = auto()
```

**Use Cases**:
- Need method-like behavior
- Complex enum logic
- Error categories with structured handling

---

## 7. Complex Type Composition

### 7.1 Container Types

**Dictionaries with Typed Values**:
```python
LossFnInputs: TypeAlias = Dict[str, TensorData]
# Used as: loss_fn_inputs: LossFnInputs

class Datum(StrictBase):
    loss_fn_inputs: LossFnInputs
    model_input: ModelInput
```

**Generic Data**:
```python
class GenericEvent(BaseModel):
    event_data: Dict[str, object] = {}

class TrainingRun(BaseModel):
    user_metadata: dict[str, str] | None = None
```

### 7.2 Union of Containers

**List of Union Types**:
```python
class TelemetrySendRequest(StrictBase):
    events: List[TelemetryEvent]
    # TelemetryEvent = Union[SessionStartEvent, SessionEndEvent, ...]

class ForwardBackwardInput(StrictBase):
    data: List[Datum]
```

**Sequences vs Lists**:
```python
# For input validation (stricter)
class ModelInput(StrictBase):
    chunks: List[ModelInputChunk]

# For output flexibility (looser)
class SampleResponse(BaseModel):
    sequences: Sequence[SampledSequence]
```

---

## 8. Serialization and Deserialization

### 8.1 Custom Field Serializers

**Base64 Encoding for Binary Data**:
```python
class ImageChunk(StrictBase):
    data: bytes

    @field_validator("data", mode="before")
    @classmethod
    def validate_data(cls, value: Union[bytes, str]) -> bytes:
        if isinstance(value, str):
            return base64.b64decode(value)
        return value

    @field_serializer("data")
    def serialize_data(self, value: bytes) -> str:
        return base64.b64encode(value).decode("utf-8")
```

**Result**:
- Incoming JSON: `{"data": "iVBORw0KGgo...", "format": "png"}`
- Internal: `bytes`
- Outgoing JSON: base64 encoded string

### 8.2 Model-level Construction

**construct() method** (bypasses validation):
```python
# From _models.py - build() function
def build(
    base_model_cls: Callable[P, _BaseModelT],
    *args: P.args,
    **kwargs: P.kwargs,
) -> _BaseModelT:
    """Construct a BaseModel class without validation."""
    if args:
        raise TypeError("Positional arguments not supported")

    return cast(_BaseModelT, construct_type(type_=base_model_cls, value=kwargs))
```

**construct_type() function**:
- Loose coercion with nested value construction
- Handles discriminated unions intelligently
- Recursively constructs nested types
- Converts datetime strings
- Type-safe without full validation

### 8.3 DateTime Handling
```python
from datetime import datetime, date

class Checkpoint(BaseModel):
    time: datetime
    # Auto-parsed from ISO strings

class TrainingRun(BaseModel):
    last_request_time: datetime
    # Auto-parsed from ISO strings
```

---

## 9. Type Compatibility and Version Handling (_compat.py)

### 9.1 Pydantic v1 vs v2 Abstraction

**Version Detection**:
```python
PYDANTIC_V2 = pydantic.VERSION.startswith("2.")
```

**Parsing**:
```python
def parse_obj(model: type[_ModelT], value: object) -> _ModelT:
    if PYDANTIC_V2:
        return model.model_validate(value)
    else:
        return model.parse_obj(value)
```

**Field Access**:
```python
def field_get_default(field: FieldInfo) -> Any:
    value = field.get_default()
    if PYDANTIC_V2:
        from pydantic_core import PydanticUndefined
        if value == PydanticUndefined:
            return None
        return value
    return value
```

**Model Dump**:
```python
def model_dump(model: pydantic.BaseModel, ...) -> dict[str, Any]:
    if PYDANTIC_V2:
        return model.model_dump(...)
    else:
        return model.dict(...)
```

### 9.2 Generic Model Support

```python
if TYPE_CHECKING:
    class GenericModel(pydantic.BaseModel): ...
else:
    if PYDANTIC_V2:
        class GenericModel(pydantic.BaseModel): ...
    else:
        import pydantic.generics
        class GenericModel(pydantic.generics.GenericModel, pydantic.BaseModel): ...
```

---

## 10. Advanced Type Patterns

### 10.1 Inherited Model Composition

**Training Run with Nested Checkpoints**:
```python
class TrainingRun(BaseModel):
    training_run_id: str
    base_model: str
    model_owner: str
    is_lora: bool
    corrupted: bool = False
    lora_rank: int | None = None
    last_request_time: datetime
    last_checkpoint: Checkpoint | None = None
    last_sampler_checkpoint: Checkpoint | None = None
    user_metadata: dict[str, str] | None = None
```

### 10.2 Multi-step Validation

**Datum with Custom Tensor Conversion**:
```python
class Datum(StrictBase):
    loss_fn_inputs: LossFnInputs
    model_input: ModelInput

    @model_validator(mode="before")
    @classmethod
    def convert_tensors(cls, data: Any) -> Any:
        """Convert torch.Tensor and numpy arrays to TensorData"""
        ...
```

### 10.3 Computed Properties

**ModelInput with length calculation**:
```python
class ModelInput(StrictBase):
    chunks: List[ModelInputChunk]

    @property
    def length(self) -> int:
        """Return the total context length used by this ModelInput."""
        return sum(chunk.length for chunk in self.chunks)
```

---

## 11. Type System Requirements for Pristine

### 11.1 Core Capabilities Needed

1. **Discriminated Unions**
   - `Union[Type1 | Type2 | Type3]` with discriminator field
   - Smart deserialization based on discriminator value
   - Fallback to sequential validation

2. **Literal Types**
   - `Literal["value1" | "value2"]` for enums
   - String unions for discriminators
   - Type-safe at compile and runtime

3. **Optional Fields**
   - `Field | nil` equivalents
   - Default values
   - Smart handling of missing vs null

4. **Custom Validators**
   - Pre-validation transformations (e.g., base64 decode)
   - Post-validation transformations
   - Model-level validators
   - Field-level validators

5. **Serializers**
   - Custom serialization (e.g., base64 encode)
   - Nested structure flattening/unflattening
   - Type conversion for wire format

6. **Container Types**
   - `List[T]` and `Sequence[T]` (with different semantics)
   - `Dict[K, V]` with typed values
   - Nested lists: `List[List[T]]`

7. **Nested Model Composition**
   - Arbitrary nesting depth
   - Mutual dependencies
   - Optional nested types

8. **Field Configuration**
   - Protected namespaces (for `model_*` fields)
   - Field aliases
   - Extra field handling (forbid vs ignore)
   - Immutability (frozen)

9. **Type Coercion**
   - String -> DateTime
   - Int -> Float
   - String -> Base64 Bytes
   - Array -> TensorData
   - Numpy/PyTorch arrays -> TensorData

10. **Enum Support**
    - Literal-based enums
    - StrEnum-based enums
    - TypeAlias pattern

### 11.2 Advanced Requirements

- Generic types `Generic[T]`
- Forward references
- Union resolution strategy ordering
- Field inheritance from base models
- Metadata preservation for discriminators
- JSON round-trip preservation

---

*Document created: 2025-12-28*
*Source: Agent analysis of Tinker Python SDK type system*
