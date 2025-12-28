# Pristine Architecture Audit: Types and Schema Mapping

**Date**: 2025-12-28
**Auditor**: Claude Code
**Scope**: Tinker Python SDK types/schema system vs Pristine/Sinter Elixir system

---

## 1. Executive Summary

The Tinker Python SDK uses Pydantic v2 for schema definition, validation, and serialization. The system defines ~60+ type models across request/response objects, with sophisticated features including:

- Two base model classes (`StrictBase` for requests, `BaseModel` for responses)
- Discriminated unions for polymorphic types
- Field aliases for JSON serialization
- Custom validators and serializers
- Literal types for type discrimination
- Optional fields with `None` defaults
- Complex nested types (unions of objects)

**Current State**: Sinter provides a solid foundation for schema definition and validation. Pristine's manifest schema is minimal. The Tinkex Elixir port has manually translated ~60 types using Sinter schemas, demonstrating the approach works but revealing gaps in Sinter's capabilities.

**Key Gaps Identified**:
1. No first-class discriminated union support in Sinter
2. Missing field alias/serialization alias support
3. No custom validator/serializer hooks per field
4. No Literal type enforcement (only `choices` constraint)
5. No bytes type with base64 serialization
6. Missing model configuration (strict vs lenient extra fields)

---

## 2. Tinker Type System Deep Dive

### 2.1 Base Model Classes

**Source**: `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/_models.py:79-98`

```python
class StrictBase(pydantic.BaseModel):
    """Don't allow extra fields, so user errors are caught earlier.
    Use this for request types."""
    model_config = ConfigDict(frozen=True, extra="forbid")

class BaseModel(pydantic.BaseModel):
    """Use for classes that may appear in responses.
    Allow extra fields, so old clients can still work."""
    model_config = ConfigDict(frozen=True, extra="ignore")
```

**Key Characteristics**:
- `StrictBase`: Requests - rejects unknown fields
- `BaseModel`: Responses - ignores unknown fields (forward compatibility)
- Both are frozen (immutable after construction)

**Sinter Equivalent**: Sinter has `strict: true/false` in schema config.

**Gap**: Sinter doesn't distinguish request vs response schemas semantically.

### 2.2 Type Patterns Observed

#### 2.2.1 Simple Field Types

**Source**: `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/types/sampling_params.py:1-26`

```python
class SamplingParams(BaseModel):
    max_tokens: Optional[int] = None
    seed: Optional[int] = None
    stop: Union[str, Sequence[str], Sequence[int], None] = None
    temperature: float = 1
    top_k: int = -1
    top_p: float = 1
```

**Observations**:
- `Optional[T]` = T | None with None default
- `Union[A, B, C, None]` = complex union allowing multiple types
- Primitive defaults (int, float)
- Docstrings as field descriptions

**Sinter Mapping**:
- `Optional[int]` -> `{:nullable, :integer}` with `optional: true`
- `Union[str, Sequence[str], Sequence[int], None]` -> `{:union, [:string, {:array, :string}, {:array, :integer}, :null]}`

#### 2.2.2 Literal Types (Discriminators)

**Source**: `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/types/sample_request.py:57`

```python
type: Literal["sample"] = "sample"
```

**Source**: `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/types/encoded_text_chunk.py:14`

```python
type: Literal["encoded_text"] = "encoded_text"
```

**Source**: `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/types/image_chunk.py:25`

```python
type: Literal["image"] = "image"
format: Literal["png", "jpeg"]
```

**Pattern**: `Literal` types serve two purposes:
1. Type discrimination in unions (the `type` field)
2. Enum-like constraints (`format: Literal["png", "jpeg"]`)

**Sinter Mapping**:
- `Literal["value"]` -> `choices: ["value"]` constraint (works but verbose)
- Discriminator pattern requires manual handling

**Gap**: No native `{:literal, value}` type in Sinter.

#### 2.2.3 Discriminated Unions

**Source**: `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/types/model_input_chunk.py:11-13`

```python
ModelInputChunk: TypeAlias = Annotated[
    Union[EncodedTextChunk, ImageAssetPointerChunk, ImageChunk],
    PropertyInfo(discriminator="type")
]
```

**Source**: `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/_models.py:336-398`

The `_build_discriminated_union_meta` function builds a mapping from discriminator values to variant types:

```python
class DiscriminatorDetails:
    field_name: str        # e.g., "type"
    field_alias_from: str  # JSON field name if aliased
    mapping: dict[str, type]  # e.g., {"encoded_text": EncodedTextChunk, "image": ImageChunk}
```

**Sinter Current**: Uses `{:union, [...]}` and validates by trying each type:

```elixir
# Tinkex ModelInput schema
{:chunks, {:array, {:union, [
  {:object, EncodedTextChunk.schema()},
  {:object, ImageChunk.schema()},
  {:object, ImageAssetPointerChunk.schema()}
]}}, [optional: true, default: []]}
```

**Gap**: Sinter tries union types sequentially. No discriminator-based fast path.

#### 2.2.4 Nested Object Types

**Source**: `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/types/datum.py:25-30`

```python
class Datum(StrictBase):
    loss_fn_inputs: LossFnInputs  # Dict[str, TensorData]
    model_input: ModelInput
```

**Source**: `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/types/get_info_response.py:23-34`

```python
class GetInfoResponse(BaseModel):
    model_data: ModelData  # Nested object
    model_id: ModelID
    is_lora: Optional[bool] = None
```

**Sinter Mapping**: Works well with `{:object, Schema.t()}`:

```elixir
# Tinkex Datum schema
{:model_input, {:object, ModelInput.schema()}, [required: true]}
```

#### 2.2.5 Custom Validators and Serializers

**Source**: `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/types/image_chunk.py:27-38`

```python
@field_validator("data", mode="before")
@classmethod
def validate_data(cls, value: Union[bytes, str]) -> bytes:
    """Deserialize base64 string to bytes if needed."""
    if isinstance(value, str):
        return base64.b64decode(value)
    return value

@field_serializer("data")
def serialize_data(self, value: bytes) -> str:
    """Serialize bytes to base64 string for JSON."""
    return base64.b64encode(value).decode("utf-8")
```

**Source**: `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/types/datum.py:31-44`

```python
@model_validator(mode="before")
@classmethod
def convert_tensors(cls, data: Any) -> Any:
    """Convert torch.Tensor and numpy arrays to TensorData during construction."""
    # Complex pre-processing logic
```

**Sinter Equivalent**: Only `post_validate` function at schema level, not per-field.

**Gap**: No per-field validators/serializers in Sinter.

#### 2.2.6 Field Aliases

**Source**: `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/_utils/_transform.py:42-69`

```python
class PropertyInfo:
    alias: str | None       # JSON field name differs from Python name
    format: PropertyFormat  # "iso8601", "base64", "custom"
    discriminator: str      # For union discrimination
```

**Usage Pattern**: `Annotated[str, PropertyInfo(alias='accountHolderName')]`

**Sinter Equivalent**: `Sinter.Transform` module handles key aliases:

```elixir
# Sinter.Transform supports:
transform(data, aliases: %{field_name: "jsonFieldName"}, formats: %{...})
```

**Gap**: Aliases not integrated into schema definition itself.

#### 2.2.7 Type Aliases (Simple Enums)

**Source**: `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/types/stop_reason.py:5`

```python
StopReason: TypeAlias = Literal["length", "stop"]
```

**Source**: `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/types/tensor_dtype.py:5`

```python
TensorDtype: TypeAlias = Literal["int64", "float32"]
```

**Source**: `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/types/checkpoint.py:8`

```python
CheckpointType = Literal["training", "sampler"]
```

**Sinter Mapping**: Use `choices` constraint:

```elixir
{:stop_reason, :string, [choices: ["length", "stop"]]}
{:dtype, :string, [choices: ["int64", "float32"]]}
```

#### 2.2.8 Complex Union Types (Response Variants)

**Source**: `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/types/future_retrieve_response.py:16-26`

```python
FutureRetrieveResponse: TypeAlias = Union[
    TryAgainResponse,
    ForwardBackwardOutput,
    OptimStepResponse,
    SaveWeightsResponse,
    LoadWeightsResponse,
    SaveWeightsForSamplerResponse,
    CreateModelResponse,
    UnloadModelResponse,
    RequestFailedResponse,
]
```

**Pattern**: Large union of response types, typically discriminated by a `type` field.

**Sinter Mapping**: Would require:
```elixir
{:union, [
  {:object, TryAgainResponse.schema()},
  {:object, ForwardBackwardOutput.schema()},
  # ... many more
]}
```

**Challenge**: No discriminator optimization; validation tries each type.

#### 2.2.9 Bytes with Base64

**Source**: `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/types/image_chunk.py:12-13`

```python
data: bytes
"""Image data as bytes"""
```

With custom serializer/validator for base64 encoding.

**Sinter Gap**: No `:bytes` type. Current workaround uses `:string` and manual encoding.

**Tinkex Workaround** (`/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/types/image_chunk.ex:43`):

```elixir
{:data, :string, [required: true]}  # Stores base64 string
```

---

## 3. Sinter Type System Analysis

### 3.1 Supported Types

**Source**: `/home/home/p/g/n/sinter/lib/sinter/types.ex:40-62`

```elixir
@type primitive_type ::
  :string | :integer | :float | :boolean | :atom | :any | :map |
  :date | :datetime | :uuid | :null

@type composite_type ::
  {:array, type_spec()} |
  {:array, type_spec(), keyword()} |  # with constraints
  {:union, [type_spec()]} |
  {:tuple, [type_spec()]} |
  {:map, type_spec(), type_spec()} |
  {:nullable, type_spec()} |
  {:object, Schema.t() | [Schema.field_spec()]}
```

### 3.2 Constraints

**Source**: `/home/home/p/g/n/sinter/lib/sinter/types.ex:64-75`

```elixir
@type constraint ::
  {:min_length, pos_integer()} |
  {:max_length, pos_integer()} |
  {:min_items, non_neg_integer()} |
  {:max_items, pos_integer()} |
  {:gt, number()} |
  {:gteq, number()} |
  {:lt, number()} |
  {:lteq, number()} |
  {:format, Regex.t()} |
  {:choices, [term()]}
```

### 3.3 Schema Definition

**Source**: `/home/home/p/g/n/sinter/lib/sinter/schema.ex:149-182`

```elixir
@spec define([field_spec()], keyword()) :: t()
def define(field_specs, opts \\ []) when is_list(field_specs) do
  # Validates specs, normalizes fields, builds config
end
```

**Field Options** (`line 99-117`):
```elixir
@field_opts_schema NimbleOptions.new!(
  required: [type: :boolean],
  optional: [type: :boolean],
  default: [type: :any],
  description: [type: :string],
  example: [type: :any],
  min_length: [type: :non_neg_integer],
  max_length: [type: :non_neg_integer],
  # ... numeric constraints
  format: [type: :any],
  choices: [type: {:list, :any}],
  dspex_field_type: [type: :atom]  # DSPEx metadata
)
```

---

## 4. Pristine Manifest Schema Analysis

### 4.1 Current Schema

**Source**: `/home/home/p/g/n/pristine/lib/pristine/manifest/schema.ex:9-18`

```elixir
def schema do
  Schema.define([
    {:name, :string, [required: true]},
    {:version, :string, [required: true]},
    {:endpoints, {:array, :map}, [required: true]},
    {:types, :map, [required: true]},
    {:policies, :map, [optional: true]},
    {:defaults, :map, [optional: true]}
  ])
end
```

### 4.2 Type Compilation

**Source**: `/home/home/p/g/n/pristine/lib/pristine/core/types.ex:9-93`

Current type compilation is very basic:

```elixir
defp resolve_type(defn) when is_map(defn) do
  type = Map.get(defn, :type) || Map.get(defn, "type") || "string"

  case normalize_key(type) do
    "string" -> :string
    "integer" -> :integer
    "float" -> :float
    "number" -> :float
    "boolean" -> :boolean
    "map" -> :map
    "object" -> :map
    "array" -> {:array, resolve_array_item(defn)}
    _other -> :any
  end
end
```

**Limitations**:
- No union type support
- No nested object schema compilation
- No discriminator support
- Arrays only support single item type (no union items)

---

## 5. Gap Analysis

### 5.1 Critical Gaps (Must Fix for Tinker Compatibility)

| Feature | Tinker | Sinter | Gap Severity |
|---------|--------|--------|--------------|
| Discriminated Unions | Full support via `PropertyInfo(discriminator="type")` | None - sequential try | **HIGH** - Performance and correctness |
| Field Aliases | `PropertyInfo(alias="jsonName")` | Only in Transform, not schema | **MEDIUM** - Usability |
| Literal Type | `Literal["value"]` | Only via `choices: [...]` | **MEDIUM** - Semantics |
| Per-field Validators | `@field_validator` | None | **HIGH** - Complex types |
| Per-field Serializers | `@field_serializer` | None | **HIGH** - bytes/base64 |
| Bytes Type | Native `bytes` | None | **MEDIUM** - Images |
| Schema Mode (strict/lenient) | `extra="forbid"` vs `extra="ignore"` | `strict: true/false` | **LOW** - Already supported |

### 5.2 Secondary Gaps

| Feature | Tinker | Sinter | Gap Severity |
|---------|--------|--------|--------------|
| Model-level Validators | `@model_validator(mode="before")` | Only `post_validate` | **MEDIUM** |
| Type References | Forward references | Module references | **LOW** - Elixir handles |
| Computed Properties | `@property` | Not in schema | **LOW** - Elixir functions |
| Pydantic V2 Config | `model_config = ConfigDict(...)` | Schema config | **LOW** |

### 5.3 Tinkex Manual Workarounds

The Tinkex port shows how gaps are currently handled:

1. **Discriminated Unions**: Manual union with try-each semantics
   - `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/types/model_input.ex:15-24`

2. **Field Aliases**: Custom Jason.Encoder implementations
   - `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/types/image_chunk.ex:102-108`

3. **Bytes/Base64**: Store as string, encode/decode manually
   - `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/types/image_chunk.ex:81-89`

4. **Optional Field Omission**: `SchemaCodec.omit_nil_fields/2`
   - `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/types/sample_request.ex:71-77`

---

## 6. Recommended Changes

### 6.1 Sinter Enhancements (Priority Order)

#### 6.1.1 Discriminated Union Support (P0)

Add discriminator metadata to union types:

```elixir
# New type syntax
{:discriminated_union, [
  discriminator: "type",
  variants: %{
    "encoded_text" => EncodedTextChunk.schema(),
    "image" => ImageChunk.schema(),
    "image_asset_pointer" => ImageAssetPointerChunk.schema()
  }
]}

# Or annotation-based
{:union, [
  {:object, EncodedTextChunk.schema()},
  {:object, ImageChunk.schema()}
], discriminator: "type"}
```

**Implementation Location**: `/home/home/p/g/n/sinter/lib/sinter/types.ex`

#### 6.1.2 Field Alias Support (P1)

Add alias option to field specifications:

```elixir
{:account_holder_name, :string, [required: true, alias: "accountHolderName"]}
```

**Implementation Locations**:
- Schema: `/home/home/p/g/n/sinter/lib/sinter/schema.ex:99-117` (add to opts schema)
- Validator: `/home/home/p/g/n/sinter/lib/sinter/validator.ex:237-243` (lookup by alias)
- Transform: `/home/home/p/g/n/sinter/lib/sinter/transform.ex` (already supports)

#### 6.1.3 Literal Type (P1)

Add explicit literal type for single-value enforcement:

```elixir
{:type, {:literal, "sample"}, []}
# Equivalent to but more semantic than:
{:type, :string, [choices: ["sample"]]}
```

#### 6.1.4 Per-Field Transform Hooks (P2)

Add transform functions to field specifications:

```elixir
{:data, :string, [
  required: true,
  on_validate: &Base.decode64/1,   # Input transformation
  on_serialize: &Base.encode64/1   # Output transformation
]}
```

#### 6.1.5 Bytes Type (P2)

Add native bytes type with base64 serialization:

```elixir
{:image_data, :bytes, [required: true]}
# Automatically handles base64 encoding/decoding
```

### 6.2 Pristine Manifest Schema Enhancements

#### 6.2.1 Enhanced Type Definition Format

Current:
```elixir
{:types, :map, [required: true]}
```

Proposed manifest type definition:
```yaml
types:
  SampleRequest:
    base: StrictBase  # or ResponseBase
    fields:
      prompt:
        type: ModelInput
        required: true
      num_samples:
        type: integer
        default: 1
      type:
        type: literal
        value: "sample"
```

#### 6.2.2 Enhanced Type Compiler

**Location**: `/home/home/p/g/n/pristine/lib/pristine/core/types.ex`

Add support for:
- Union types: `type: union`, `variants: [...]`
- Nested objects: `type: object`, `schema: ...`
- Discriminated unions: `type: discriminated_union`, `discriminator: "type"`
- Literals: `type: literal`, `value: "..."

---

## 7. Concrete Next Steps (TDD Approach)

### 7.1 Phase 1: Discriminated Union Support in Sinter

**Tests to Add** (`/home/home/p/g/n/sinter/test/sinter/types_test.exs`):

```elixir
describe "discriminated union validation" do
  test "validates correct variant based on discriminator field" do
    chunk_schema = Schema.define([
      {:type, :string, [required: true]},
      {:tokens, {:array, :integer}, [optional: true]},
      {:data, :string, [optional: true]}
    ])

    schema = Schema.define([
      {:chunk, {:discriminated_union,
        discriminator: "type",
        variants: %{
          "encoded_text" => encoded_text_schema(),
          "image" => image_schema()
        }
      }, [required: true]}
    ])

    # Should match encoded_text variant
    assert {:ok, _} = Validator.validate(schema, %{
      "chunk" => %{"type" => "encoded_text", "tokens" => [1, 2, 3]}
    })

    # Should match image variant
    assert {:ok, _} = Validator.validate(schema, %{
      "chunk" => %{"type" => "image", "data" => "base64..."}
    })

    # Should fail for unknown discriminator
    assert {:error, [%{code: :discriminator}]} = Validator.validate(schema, %{
      "chunk" => %{"type" => "unknown"}
    })
  end

  test "provides clear error for missing discriminator field" do
    # ...
  end

  test "validates nested discriminated unions" do
    # ...
  end
end
```

### 7.2 Phase 2: Field Alias Support

**Tests to Add** (`/home/home/p/g/n/sinter/test/sinter/validator_test.exs`):

```elixir
describe "field alias validation" do
  test "validates fields by their alias names in input" do
    schema = Schema.define([
      {:account_name, :string, [required: true, alias: "accountName"]}
    ])

    # Input uses alias
    assert {:ok, %{"account_name" => "Test"}} =
      Validator.validate(schema, %{"accountName" => "Test"})
  end

  test "validates fields by canonical name when alias not used" do
    # ...
  end

  test "schema.field_aliases/1 returns alias mapping" do
    # ...
  end
end
```

### 7.3 Phase 3: Literal Type

**Tests to Add** (`/home/home/p/g/n/sinter/test/sinter/types_test.exs`):

```elixir
describe "literal type validation" do
  test "validates exact literal value" do
    assert {:ok, "sample"} = Types.validate({:literal, "sample"}, "sample", [])
    assert {:error, _} = Types.validate({:literal, "sample"}, "other", [])
  end

  test "literal appears in JSON schema as const" do
    assert %{"const" => "sample"} = Types.to_json_schema({:literal, "sample"})
  end
end
```

### 7.4 Phase 4: Per-Field Transform Hooks

**Tests to Add**:

```elixir
describe "field transform hooks" do
  test "on_validate transforms input before validation" do
    schema = Schema.define([
      {:data, :binary, [
        required: true,
        on_validate: &Base.decode64!/1
      ]}
    ])

    # Input is base64, stored as binary
    assert {:ok, %{"data" => <<1, 2, 3>>}} =
      Validator.validate(schema, %{"data" => "AQID"})
  end
end
```

### 7.5 Phase 5: Pristine Type Compiler Enhancement

**Tests to Add** (`/home/home/p/g/n/pristine/test/pristine/core/types_test.exs`):

```elixir
describe "compile/1 with advanced types" do
  test "compiles union type definitions" do
    types = %{
      "ModelInputChunk" => %{
        "type" => "union",
        "variants" => [
          %{"$ref" => "EncodedTextChunk"},
          %{"$ref" => "ImageChunk"}
        ],
        "discriminator" => "type"
      }
    }

    compiled = Types.compile(types)
    assert {:discriminated_union, opts} = compiled["ModelInputChunk"]
    assert opts[:discriminator] == "type"
  end

  test "compiles literal type definitions" do
    types = %{
      "SampleType" => %{
        "type" => "literal",
        "value" => "sample"
      }
    }

    compiled = Types.compile(types)
    assert {:literal, "sample"} = compiled["SampleType"]
  end
end
```

---

## 8. Implementation Priority Matrix

| Enhancement | Effort | Impact | Priority | Blocks |
|-------------|--------|--------|----------|--------|
| Discriminated Unions | HIGH | HIGH | P0 | ModelInputChunk, FutureRetrieveResponse |
| Field Aliases | MEDIUM | MEDIUM | P1 | JSON wire compatibility |
| Literal Type | LOW | MEDIUM | P1 | Type discrimination |
| Per-field Transforms | HIGH | HIGH | P2 | ImageChunk.data, TensorData |
| Bytes Type | MEDIUM | MEDIUM | P2 | Image handling |
| Enhanced Type Compiler | MEDIUM | HIGH | P1 | Manifest-driven generation |

---

## 9. Appendix: File References

### Tinker Python SDK
- Base models: `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/_models.py`
- Type definitions: `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/types/`
- Transform utilities: `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/_utils/_transform.py`

### Pristine Elixir System
- Core types: `/home/home/p/g/n/pristine/lib/pristine/core/types.ex`
- Manifest schema: `/home/home/p/g/n/pristine/lib/pristine/manifest/schema.ex`

### Sinter Library
- Main module: `/home/home/p/g/n/sinter/lib/sinter.ex`
- Schema: `/home/home/p/g/n/sinter/lib/sinter/schema.ex`
- Types: `/home/home/p/g/n/sinter/lib/sinter/types.ex`
- Validator: `/home/home/p/g/n/sinter/lib/sinter/validator.ex`
- Transform: `/home/home/p/g/n/sinter/lib/sinter/transform.ex`

### Tinkex (Existing Port)
- Type modules: `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/types/`
- Examples of manual porting patterns

---

## 10. Conclusion

The Tinker Python SDK has a sophisticated type system built on Pydantic v2. The Sinter library provides a solid foundation but requires several enhancements to fully support automatic type generation from Tinker specifications:

1. **Discriminated unions** are the most critical gap - they affect both correctness and performance
2. **Field aliases** are needed for JSON wire compatibility
3. **Per-field transforms** enable complex types like base64-encoded bytes
4. **The Pristine type compiler** needs enhancement to generate Sinter schemas from manifest type definitions

The Tinkex manual port demonstrates that the current system works with workarounds, but automated generation will require the Sinter enhancements outlined above.
