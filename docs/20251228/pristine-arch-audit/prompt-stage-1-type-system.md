# Stage 1: Type System Parity Implementation Prompt

**Estimated Effort**: 8-10 days
**Prerequisites**: Stage 0 Complete
**Goal**: All tests pass, no warnings, no errors, no dialyzer errors, no `mix credo --strict` errors

---

## Context

You are implementing Stage 1 of the Pristine architecture buildout. This stage focuses on bringing Sinter to full Pydantic feature parity for expressing Tinker SDK types. The key additions are discriminated unions, pre-validation hooks, field-level validators, and field aliases.

### What Stage 0 Completed

- Dialyzer and Credo configured
- Codegen produces @doc and @spec
- Literal type `{:literal, value}` in Sinter
- `mix pristine.validate` task
- Idempotency header support

---

## Required Reading

### Architecture Documentation
```
/home/home/p/g/n/pristine/docs/20251228/pristine-arch-audit/overview.md
/home/home/p/g/n/pristine/docs/20251228/pristine-arch-audit/gap-analysis.md
/home/home/p/g/n/pristine/docs/20251228/pristine-arch-audit/01-types-schema-mapping.md
```

### Sinter Source Files (Primary Focus)
```
/home/home/p/g/n/sinter/lib/sinter.ex
/home/home/p/g/n/sinter/lib/sinter/schema.ex
/home/home/p/g/n/sinter/lib/sinter/types.ex
/home/home/p/g/n/sinter/lib/sinter/validator.ex
/home/home/p/g/n/sinter/lib/sinter/transform.ex
/home/home/p/g/n/sinter/lib/sinter/json_schema.ex
/home/home/p/g/n/sinter/lib/sinter/error.ex
```

### Sinter Test Files
```
/home/home/p/g/n/sinter/test/sinter/schema_test.exs
/home/home/p/g/n/sinter/test/sinter/types_test.exs
/home/home/p/g/n/sinter/test/sinter/validator_test.exs
```

### Reference: Tinker Type Patterns
```
/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/_models.py
/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/types/model_input_chunk.py
/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/types/datum.py
/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/types/image_chunk.py
```

### Reference: Tinkex Type Implementation
```
/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/types/model_input.ex
/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/types/image_chunk.ex
```

---

## Tasks

### Task 1.1: Discriminated Union Support (3-4 days)

**Gap Addressed**: GAP-001

**Files to Modify**:
- `/home/home/p/g/n/sinter/lib/sinter/types.ex`
- `/home/home/p/g/n/sinter/lib/sinter/validator.ex`
- `/home/home/p/g/n/sinter/lib/sinter/json_schema.ex`

**TDD Steps**:

1. **Write Comprehensive Tests First**:

```elixir
# /home/home/p/g/n/sinter/test/sinter/discriminated_union_test.exs
defmodule Sinter.DiscriminatedUnionTest do
  use ExUnit.Case, async: true

  alias Sinter.{Schema, Validator, Types, JsonSchema}

  # Test schemas
  def encoded_text_schema do
    Schema.define([
      {:type, {:literal, "encoded_text"}, [required: true]},
      {:tokens, {:array, :integer}, [required: true]}
    ])
  end

  def image_schema do
    Schema.define([
      {:type, {:literal, "image"}, [required: true]},
      {:data, :string, [required: true]},
      {:format, :string, [choices: ["png", "jpeg"], required: true]}
    ])
  end

  def image_pointer_schema do
    Schema.define([
      {:type, {:literal, "image_asset_pointer"}, [required: true]},
      {:asset_id, :string, [required: true]}
    ])
  end

  describe "discriminated union type validation" do
    test "validates correct encoded_text variant" do
      union_type = {:discriminated_union, [
        discriminator: "type",
        variants: %{
          "encoded_text" => encoded_text_schema(),
          "image" => image_schema(),
          "image_asset_pointer" => image_pointer_schema()
        }
      ]}

      data = %{"type" => "encoded_text", "tokens" => [1, 2, 3]}

      assert {:ok, validated} = Types.validate(union_type, data, [])
      assert validated["type"] == "encoded_text"
      assert validated["tokens"] == [1, 2, 3]
    end

    test "validates correct image variant" do
      union_type = {:discriminated_union, [
        discriminator: "type",
        variants: %{
          "encoded_text" => encoded_text_schema(),
          "image" => image_schema()
        }
      ]}

      data = %{"type" => "image", "data" => "base64data", "format" => "png"}

      assert {:ok, validated} = Types.validate(union_type, data, [])
      assert validated["type"] == "image"
    end

    test "returns error for unknown discriminator value" do
      union_type = {:discriminated_union, [
        discriminator: "type",
        variants: %{
          "encoded_text" => encoded_text_schema(),
          "image" => image_schema()
        }
      ]}

      data = %{"type" => "unknown", "foo" => "bar"}

      assert {:error, error} = Types.validate(union_type, data, [])
      assert error.code == :unknown_discriminator
      assert error.message =~ "unknown"
    end

    test "returns error for missing discriminator field" do
      union_type = {:discriminated_union, [
        discriminator: "type",
        variants: %{
          "encoded_text" => encoded_text_schema()
        }
      ]}

      data = %{"tokens" => [1, 2, 3]}

      assert {:error, error} = Types.validate(union_type, data, [])
      assert error.code == :missing_discriminator
    end

    test "returns variant validation errors with context" do
      union_type = {:discriminated_union, [
        discriminator: "type",
        variants: %{
          "encoded_text" => encoded_text_schema()
        }
      ]}

      # Missing required 'tokens' field
      data = %{"type" => "encoded_text"}

      assert {:error, errors} = Types.validate(union_type, data, [])
      # Should mention the missing tokens field
    end

    test "handles atom discriminator values" do
      atom_text_schema = Schema.define([
        {:type, {:literal, :text}, [required: true]},
        {:content, :string, [required: true]}
      ])

      union_type = {:discriminated_union, [
        discriminator: "type",
        variants: %{
          :text => atom_text_schema
        }
      ]}

      data = %{"type" => :text, "content" => "hello"}
      assert {:ok, _} = Types.validate(union_type, data, [])
    end

    test "works with string key discriminator" do
      union_type = {:discriminated_union, [
        discriminator: "type",
        variants: %{
          "encoded_text" => encoded_text_schema()
        }
      ]}

      # String keys
      data = %{"type" => "encoded_text", "tokens" => [1]}
      assert {:ok, _} = Types.validate(union_type, data, [])
    end

    test "works with atom key discriminator" do
      union_type = {:discriminated_union, [
        discriminator: :type,
        variants: %{
          "encoded_text" => encoded_text_schema()
        }
      ]}

      # Atom keys
      data = %{type: "encoded_text", tokens: [1]}
      assert {:ok, _} = Types.validate(union_type, data, [])
    end
  end

  describe "discriminated union in schema fields" do
    test "validates discriminated union as field type" do
      chunk_union = {:discriminated_union, [
        discriminator: "type",
        variants: %{
          "encoded_text" => encoded_text_schema(),
          "image" => image_schema()
        }
      ]}

      parent_schema = Schema.define([
        {:chunks, {:array, chunk_union}, [required: true]}
      ])

      data = %{
        "chunks" => [
          %{"type" => "encoded_text", "tokens" => [1, 2]},
          %{"type" => "image", "data" => "abc", "format" => "png"}
        ]
      }

      assert {:ok, validated} = Validator.validate(parent_schema, data)
      assert length(validated["chunks"]) == 2
    end
  end

  describe "JSON Schema generation for discriminated unions" do
    test "generates oneOf with discriminator" do
      union_type = {:discriminated_union, [
        discriminator: "type",
        variants: %{
          "encoded_text" => encoded_text_schema(),
          "image" => image_schema()
        }
      ]}

      json_schema = JsonSchema.type_to_json_schema(union_type)

      assert json_schema["oneOf"]
      assert json_schema["discriminator"]["propertyName"] == "type"
      assert is_map(json_schema["discriminator"]["mapping"])
    end
  end
end
```

2. **Implement in types.ex**:

Add to `/home/home/p/g/n/sinter/lib/sinter/types.ex`:

```elixir
@doc """
Validates a discriminated union type.

The discriminated union uses a field (discriminator) to determine which
variant schema to validate against.

## Options

  * `:discriminator` - Field name to use as discriminator (required)
  * `:variants` - Map of discriminator value => schema (required)

## Example

    {:discriminated_union, [
      discriminator: "type",
      variants: %{
        "text" => text_schema,
        "image" => image_schema
      }
    ]}
"""
def validate({:discriminated_union, opts}, value, validation_opts) when is_map(value) do
  discriminator = Keyword.fetch!(opts, :discriminator)
  variants = Keyword.fetch!(opts, :variants)
  path = Keyword.get(validation_opts, :path, [])

  # Get discriminator value (support both string and atom keys)
  disc_value = get_discriminator_value(value, discriminator)

  case disc_value do
    nil ->
      error = %Sinter.Error{
        path: path ++ [to_string(discriminator)],
        code: :missing_discriminator,
        message: "missing discriminator field '#{discriminator}'",
        context: %{discriminator: discriminator}
      }
      {:error, error}

    disc_val ->
      # Look up variant schema
      case Map.get(variants, disc_val) || Map.get(variants, to_string(disc_val)) do
        nil ->
          valid_values = Map.keys(variants)
          error = %Sinter.Error{
            path: path ++ [to_string(discriminator)],
            code: :unknown_discriminator,
            message: "unknown discriminator value '#{disc_val}', expected one of: #{inspect(valid_values)}",
            context: %{value: disc_val, valid_values: valid_values}
          }
          {:error, error}

        variant_schema ->
          # Validate against the variant schema
          Sinter.Validator.validate(variant_schema, value, validation_opts)
      end
  end
end

def validate({:discriminated_union, _opts}, value, validation_opts) do
  path = Keyword.get(validation_opts, :path, [])
  error = %Sinter.Error{
    path: path,
    code: :type_error,
    message: "expected map for discriminated union, got #{inspect(value)}",
    context: %{expected: :map, actual: value}
  }
  {:error, error}
end

defp get_discriminator_value(map, discriminator) when is_binary(discriminator) do
  Map.get(map, discriminator) || Map.get(map, String.to_existing_atom(discriminator))
rescue
  ArgumentError -> Map.get(map, discriminator)
end

defp get_discriminator_value(map, discriminator) when is_atom(discriminator) do
  Map.get(map, discriminator) || Map.get(map, to_string(discriminator))
end
```

3. **Implement in json_schema.ex**:

```elixir
def type_to_json_schema({:discriminated_union, opts}) do
  discriminator = Keyword.fetch!(opts, :discriminator)
  variants = Keyword.fetch!(opts, :variants)

  variant_schemas = Enum.map(variants, fn {_key, schema} ->
    generate(schema)
  end)

  mapping = Enum.map(variants, fn {key, _schema} ->
    {to_string(key), "#/definitions/#{key}"}
  end) |> Map.new()

  %{
    "oneOf" => variant_schemas,
    "discriminator" => %{
      "propertyName" => to_string(discriminator),
      "mapping" => mapping
    }
  }
end
```

4. **Run Tests**:
```bash
cd /home/home/p/g/n/sinter && mix test test/sinter/discriminated_union_test.exs
```

---

### Task 1.2: Pre-validation Hooks (2 days)

**Gap Addressed**: GAP-004

**Files to Modify**:
- `/home/home/p/g/n/sinter/lib/sinter/schema.ex`
- `/home/home/p/g/n/sinter/lib/sinter/validator.ex`

**TDD Steps**:

1. **Write Tests First**:

```elixir
# /home/home/p/g/n/sinter/test/sinter/pre_validate_test.exs
defmodule Sinter.PreValidateTest do
  use ExUnit.Case, async: true

  alias Sinter.{Schema, Validator}

  describe "pre_validate option" do
    test "transforms data before validation" do
      schema = Schema.define(
        [
          {:amount, :integer, [required: true]}
        ],
        pre_validate: fn data ->
          case data do
            %{"amount" => amount} when is_binary(amount) ->
              Map.put(data, "amount", String.to_integer(amount))
            _ ->
              data
          end
        end
      )

      # String amount gets transformed to integer
      assert {:ok, %{"amount" => 42}} = Validator.validate(schema, %{"amount" => "42"})
    end

    test "pre_validate receives raw input data" do
      test_pid = self()

      schema = Schema.define(
        [{:name, :string, [required: true]}],
        pre_validate: fn data ->
          send(test_pid, {:pre_validate_called, data})
          data
        end
      )

      input = %{"name" => "test", "extra" => "field"}
      Validator.validate(schema, input)

      assert_receive {:pre_validate_called, ^input}
    end

    test "pre_validate can add fields" do
      schema = Schema.define(
        [
          {:full_name, :string, [required: true]},
          {:first_name, :string, [optional: true]},
          {:last_name, :string, [optional: true]}
        ],
        pre_validate: fn data ->
          first = Map.get(data, "first_name", "")
          last = Map.get(data, "last_name", "")
          Map.put(data, "full_name", "#{first} #{last}" |> String.trim())
        end
      )

      input = %{"first_name" => "John", "last_name" => "Doe"}
      assert {:ok, result} = Validator.validate(schema, input)
      assert result["full_name"] == "John Doe"
    end

    test "pre_validate can remove fields" do
      schema = Schema.define(
        [{:data, :map, [required: true]}],
        pre_validate: fn data ->
          Map.update(data, "data", %{}, fn d ->
            Map.drop(d, ["password", "secret"])
          end)
        end
      )

      input = %{"data" => %{"name" => "test", "password" => "secret123"}}
      assert {:ok, result} = Validator.validate(schema, input)
      refute Map.has_key?(result["data"], "password")
    end

    test "errors in pre_validate are caught and wrapped" do
      schema = Schema.define(
        [{:value, :integer, [required: true]}],
        pre_validate: fn _data ->
          raise "Pre-validation error"
        end
      )

      assert {:error, error} = Validator.validate(schema, %{"value" => 1})
      assert error.code == :pre_validate_error
    end

    test "pre_validate nil means no transformation" do
      schema = Schema.define(
        [{:name, :string, [required: true]}],
        pre_validate: nil
      )

      assert {:ok, _} = Validator.validate(schema, %{"name" => "test"})
    end

    test "pre_validate works with nested schemas" do
      inner_schema = Schema.define(
        [{:value, :integer, [required: true]}],
        pre_validate: fn data ->
          Map.update(data, "value", 0, &(&1 * 2))
        end
      )

      outer_schema = Schema.define([
        {:nested, {:object, inner_schema}, [required: true]}
      ])

      input = %{"nested" => %{"value" => 5}}
      assert {:ok, result} = Validator.validate(outer_schema, input)
      assert result["nested"]["value"] == 10
    end
  end
end
```

2. **Update Schema struct**:

In `/home/home/p/g/n/sinter/lib/sinter/schema.ex`:

```elixir
defstruct [
  fields: [],
  field_map: %{},
  config: %{
    strict: false,
    coerce: false,
    post_validate: nil,
    pre_validate: nil  # NEW
  }
]

# Update define/2 to accept pre_validate option
def define(field_specs, opts \\ []) do
  # ... existing code ...
  pre_validate = Keyword.get(opts, :pre_validate)

  config = %{
    strict: Keyword.get(opts, :strict, false),
    coerce: Keyword.get(opts, :coerce, false),
    post_validate: Keyword.get(opts, :post_validate),
    pre_validate: pre_validate
  }

  %__MODULE__{
    fields: normalized_fields,
    field_map: field_map,
    config: config
  }
end
```

3. **Update Validator**:

In `/home/home/p/g/n/sinter/lib/sinter/validator.ex`:

```elixir
def validate(%Schema{} = schema, data, opts \\ []) do
  path = Keyword.get(opts, :path, [])

  # NEW: Apply pre-validation transformation
  data = apply_pre_validation(schema, data, path)

  case data do
    {:error, _} = error -> error
    data ->
      normalized_data = normalize_input(data)
      # ... rest of existing validation
  end
end

defp apply_pre_validation(%Schema{config: %{pre_validate: nil}}, data, _path) do
  data
end

defp apply_pre_validation(%Schema{config: %{pre_validate: fun}}, data, path)
    when is_function(fun, 1) do
  try do
    fun.(data)
  rescue
    e ->
      error = %Sinter.Error{
        path: path,
        code: :pre_validate_error,
        message: "pre_validate function raised: #{Exception.message(e)}",
        context: %{exception: e}
      }
      {:error, error}
  end
end
```

4. **Run Tests**:
```bash
cd /home/home/p/g/n/sinter && mix test test/sinter/pre_validate_test.exs
```

---

### Task 1.3: Field-level Validators (2 days)

**Gap Addressed**: GAP-005

**Files to Modify**:
- `/home/home/p/g/n/sinter/lib/sinter/schema.ex`
- `/home/home/p/g/n/sinter/lib/sinter/validator.ex`

**TDD Steps**:

1. **Write Tests First**:

```elixir
# /home/home/p/g/n/sinter/test/sinter/field_validator_test.exs
defmodule Sinter.FieldValidatorTest do
  use ExUnit.Case, async: true

  alias Sinter.{Schema, Validator}

  describe "field validate option" do
    test "custom validator runs after type check" do
      schema = Schema.define([
        {:email, :string, [
          required: true,
          validate: fn value ->
            if String.contains?(value, "@"),
              do: {:ok, value},
              else: {:error, "must contain @"}
          end
        ]}
      ])

      assert {:ok, _} = Validator.validate(schema, %{"email" => "test@example.com"})
      assert {:error, [error]} = Validator.validate(schema, %{"email" => "invalid"})
      assert error.code == :custom_validation
      assert error.message =~ "@"
    end

    test "validator can transform value" do
      schema = Schema.define([
        {:name, :string, [
          required: true,
          validate: fn value ->
            {:ok, String.upcase(value)}
          end
        ]}
      ])

      assert {:ok, %{"name" => "ALICE"}} = Validator.validate(schema, %{"name" => "alice"})
    end

    test "validator receives raw value after type coercion" do
      schema = Schema.define([
        {:count, :integer, [
          required: true,
          validate: fn value ->
            if value > 0,
              do: {:ok, value},
              else: {:error, "must be positive"}
          end
        ]}
      ], coerce: true)

      assert {:ok, %{"count" => 5}} = Validator.validate(schema, %{"count" => "5"})
      assert {:error, _} = Validator.validate(schema, %{"count" => "-1"})
    end

    test "validator error includes field path" do
      schema = Schema.define([
        {:user, {:object, Schema.define([
          {:age, :integer, [
            required: true,
            validate: fn v -> if v >= 0, do: {:ok, v}, else: {:error, "must be non-negative"} end
          ]}
        ])}, [required: true]}
      ])

      assert {:error, [error]} = Validator.validate(schema, %{
        "user" => %{"age" => -5}
      })
      assert error.path == ["user", "age"]
    end

    test "multiple validators can be specified as list" do
      not_empty = fn v ->
        if String.length(v) > 0, do: {:ok, v}, else: {:error, "cannot be empty"}
      end

      max_length = fn v ->
        if String.length(v) <= 10, do: {:ok, v}, else: {:error, "too long"}
      end

      schema = Schema.define([
        {:code, :string, [
          required: true,
          validate: [not_empty, max_length]
        ]}
      ])

      assert {:ok, _} = Validator.validate(schema, %{"code" => "ABC123"})
      assert {:error, _} = Validator.validate(schema, %{"code" => ""})
      assert {:error, _} = Validator.validate(schema, %{"code" => "VERYLONGCODE123"})
    end

    test "validator only runs if field is present" do
      schema = Schema.define([
        {:optional_field, :string, [
          optional: true,
          validate: fn _ -> {:error, "always fails"} end
        ]}
      ])

      # Should pass because field is not present
      assert {:ok, _} = Validator.validate(schema, %{})
    end

    test "validator runs on nil if field is present" do
      schema = Schema.define([
        {:nullable_field, {:nullable, :string}, [
          optional: true,
          validate: fn
            nil -> {:ok, nil}
            v -> {:ok, String.upcase(v)}
          end
        ]}
      ])

      assert {:ok, %{"nullable_field" => nil}} =
        Validator.validate(schema, %{"nullable_field" => nil})
    end
  end
end
```

2. **Update Schema field options**:

In `/home/home/p/g/n/sinter/lib/sinter/schema.ex`, add `:validate` to the field options schema.

3. **Update Validator**:

In `/home/home/p/g/n/sinter/lib/sinter/validator.ex`:

```elixir
defp validate_field_value(field_name, type, value, field_opts, path, schema_opts) do
  # Existing type validation
  case Types.validate(type, value, Keyword.put(schema_opts, :path, field_path)) do
    {:ok, validated_value} ->
      # NEW: Apply custom validator(s) if present
      apply_field_validators(validated_value, field_opts, field_path)

    {:error, _} = error ->
      error
  end
end

defp apply_field_validators(value, field_opts, path) do
  case Keyword.get(field_opts, :validate) do
    nil ->
      {:ok, value}

    validators when is_list(validators) ->
      Enum.reduce_while(validators, {:ok, value}, fn validator, {:ok, val} ->
        case apply_single_validator(validator, val, path) do
          {:ok, new_val} -> {:cont, {:ok, new_val}}
          {:error, _} = err -> {:halt, err}
        end
      end)

    validator when is_function(validator, 1) ->
      apply_single_validator(validator, value, path)
  end
end

defp apply_single_validator(validator, value, path) do
  case validator.(value) do
    {:ok, new_value} ->
      {:ok, new_value}

    {:error, message} when is_binary(message) ->
      error = %Sinter.Error{
        path: path,
        code: :custom_validation,
        message: message,
        context: %{value: value}
      }
      {:error, [error]}

    {:error, %Sinter.Error{} = error} ->
      {:error, [%{error | path: path}]}
  end
end
```

4. **Run Tests**:
```bash
cd /home/home/p/g/n/sinter && mix test test/sinter/field_validator_test.exs
```

---

### Task 1.4: Field Aliases (2 days)

**Gap Addressed**: GAP-007

**Files to Modify**:
- `/home/home/p/g/n/sinter/lib/sinter/schema.ex`
- `/home/home/p/g/n/sinter/lib/sinter/validator.ex`
- `/home/home/p/g/n/sinter/lib/sinter/transform.ex`
- `/home/home/p/g/n/sinter/lib/sinter/json_schema.ex`

**TDD Steps**:

1. **Write Tests First**:

```elixir
# /home/home/p/g/n/sinter/test/sinter/field_alias_test.exs
defmodule Sinter.FieldAliasTest do
  use ExUnit.Case, async: true

  alias Sinter.{Schema, Validator, Transform, JsonSchema}

  describe "field alias in validation" do
    test "accepts input using alias name" do
      schema = Schema.define([
        {:account_name, :string, [required: true, alias: "accountName"]}
      ])

      # Input uses alias
      assert {:ok, result} = Validator.validate(schema, %{"accountName" => "Test"})
      # Result uses canonical name
      assert result["account_name"] == "Test"
    end

    test "accepts input using canonical name" do
      schema = Schema.define([
        {:account_name, :string, [required: true, alias: "accountName"]}
      ])

      # Input uses canonical name
      assert {:ok, result} = Validator.validate(schema, %{"account_name" => "Test"})
      assert result["account_name"] == "Test"
    end

    test "alias takes precedence over canonical name if both present" do
      schema = Schema.define([
        {:name, :string, [required: true, alias: "displayName"]}
      ])

      # Both present - alias wins
      input = %{"name" => "canonical", "displayName" => "alias"}
      assert {:ok, result} = Validator.validate(schema, input)
      assert result["name"] == "alias"
    end

    test "required check uses alias" do
      schema = Schema.define([
        {:user_id, :string, [required: true, alias: "userId"]}
      ])

      # Missing both alias and canonical
      assert {:error, [error]} = Validator.validate(schema, %{})
      assert error.message =~ "userId" or error.message =~ "user_id"
    end
  end

  describe "field alias in transform output" do
    test "outputs using alias name" do
      schema = Schema.define([
        {:account_name, :string, [required: true, alias: "accountName"]}
      ])

      data = %{"account_name" => "Test"}
      result = Transform.transform(data, schema: schema, use_aliases: true)

      assert result["accountName"] == "Test"
      refute Map.has_key?(result, "account_name")
    end

    test "outputs canonical name when use_aliases: false" do
      schema = Schema.define([
        {:account_name, :string, [required: true, alias: "accountName"]}
      ])

      data = %{"account_name" => "Test"}
      result = Transform.transform(data, schema: schema, use_aliases: false)

      assert result["account_name"] == "Test"
      refute Map.has_key?(result, "accountName")
    end
  end

  describe "field alias in JSON Schema" do
    test "uses alias as property name" do
      schema = Schema.define([
        {:account_name, :string, [required: true, alias: "accountName"]}
      ])

      json_schema = JsonSchema.generate(schema)

      assert Map.has_key?(json_schema["properties"], "accountName")
      refute Map.has_key?(json_schema["properties"], "account_name")
    end

    test "alias appears in required array" do
      schema = Schema.define([
        {:account_name, :string, [required: true, alias: "accountName"]}
      ])

      json_schema = JsonSchema.generate(schema)

      assert "accountName" in json_schema["required"]
    end
  end

  describe "Schema.field_aliases/1" do
    test "returns map of canonical name to alias" do
      schema = Schema.define([
        {:account_name, :string, [alias: "accountName"]},
        {:user_id, :string, [alias: "userId"]},
        {:no_alias, :string, []}
      ])

      aliases = Schema.field_aliases(schema)

      assert aliases[:account_name] == "accountName"
      assert aliases[:user_id] == "userId"
      refute Map.has_key?(aliases, :no_alias)
    end
  end
end
```

2. **Update Schema**:

Add `:alias` to field options and add `field_aliases/1` function.

3. **Update Validator**:

Modify field lookup to check both alias and canonical name.

4. **Update Transform**:

Add `use_aliases: true` option to output using aliases.

5. **Update JsonSchema**:

Use alias as property name in generated JSON Schema.

6. **Run Tests**:
```bash
cd /home/home/p/g/n/sinter && mix test test/sinter/field_alias_test.exs
```

---

## Verification Checklist

After completing all tasks:

```bash
# In Sinter
cd /home/home/p/g/n/sinter

# All tests pass
mix test

# No compilation warnings
mix compile --warnings-as-errors

# Credo passes
mix credo --strict

# Dialyzer passes
mix dialyzer

# In Pristine (ensure compatibility)
cd /home/home/p/g/n/pristine

mix test
mix compile --warnings-as-errors
```

---

## Expected Outcomes

After Stage 1 completion:

1. **Discriminated unions** work with `{:discriminated_union, [discriminator: "type", variants: %{...}]}`
2. **Pre-validation hooks** via `Schema.define([...], pre_validate: fn data -> ... end)`
3. **Field validators** via `{:field, :type, [validate: fn v -> ... end]}`
4. **Field aliases** via `{:field, :type, [alias: "jsonName"]}`
5. **JSON Schema generation** supports all new features
6. **All Tinker types can be expressed** in Sinter schemas
