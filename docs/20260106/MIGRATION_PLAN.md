# Migration Plan: Tinkex -> Pristine Integration

This document outlines the step-by-step plan to migrate from the current duplicated architecture to proper Pristine integration using **TDD/RGR (Red-Green-Refactor)** methodology throughout.

## Overview

**Current State**: ~15,000 LOC of duplicated infrastructure in examples/tinkex
**Target State**: ~4,000 LOC of domain logic using Pristine infrastructure

**Approach**: TDD-first incremental migration with continuous testing

**Methodology**: Every phase follows Red-Green-Refactor:
1. **RED** - Write failing tests that define expected behavior
2. **GREEN** - Implement minimal code to pass tests
3. **REFACTOR** - Clean up while keeping tests green

---

## Dependency Leverage Strategy

### Available Dependencies

| Dependency | Provides | Replaces in Tinkex |
|------------|----------|-------------------|
| `foundation` | Retry, backoff, circuit breaker, rate limiting, semaphores | `retry.ex`, `retry_handler.ex`, `circuit_breaker.ex`, `rate_limiter.ex`, `bytes_semaphore.ex` |
| `sinter` | Schema validation, JSON Schema, NotGiven | Type validation, `not_given.ex` |
| `multipart_ex` | Multipart/form-data encoding | `multipart/encoder.ex`, `multipart/form_serializer.ex` |
| `telemetry_reporter` | Telemetry batching, transport, backoff | `telemetry/reporter.ex`, `telemetry/reporter/*.ex` |

### Infrastructure Elimination

These tinkex modules are **entirely replaced** by deps:
- `Tinkex.Retry` -> `Foundation.Retry`
- `Tinkex.RetryHandler` -> `Foundation.Retry.Handler`
- `Tinkex.RetryConfig` -> `Foundation.Retry.Config`
- `Tinkex.CircuitBreaker` -> `Foundation.CircuitBreaker`
- `Tinkex.CircuitBreaker.Registry` -> `Foundation.CircuitBreaker.Registry`
- `Tinkex.RateLimiter` -> `Foundation.Semaphore.Limiter`
- `Tinkex.BytesSemaphore` -> `Foundation.Semaphore.Weighted`
- `Tinkex.RetrySemaphore` -> `Foundation.Semaphore.Counting`
- `Tinkex.NotGiven` -> `Sinter.NotGiven`
- `Tinkex.Multipart.*` -> `Multipart.*`
- `Tinkex.Telemetry.Reporter.*` -> `TelemetryReporter.*`

---

## Phase 0: Project Setup

**Goal**: Set up examples/tinkex as standalone Mix application with proper test infrastructure

### 0.1 Delete Current examples/tinkex

```bash
rm -rf examples/tinkex
```

This is not a refactor - it's a rewrite. The current code is too entangled to salvage.

### 0.2 Create Standalone Mix Application

```bash
mkdir -p examples/tinkex
cd examples/tinkex
mix new . --app tinkex --module Tinkex
```

### 0.3 Configure mix.exs with Pristine Dependency

Create `examples/tinkex/mix.exs`:

```elixir
defmodule Tinkex.MixProject do
  use Mix.Project

  def project do
    [
      app: :tinkex,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.html": :test
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      extra_applications: [:logger, :inets, :ssl],
      mod: {Tinkex.Application, []}
    ]
  end

  defp deps do
    [
      # Core dependency
      {:pristine, path: "../.."},

      # Pristine's transitive deps (for direct use)
      {:foundation, path: "../../../foundation"},
      {:sinter, path: "../../../sinter"},
      {:multipart_ex, path: "../../../multipart_ex"},
      {:telemetry_reporter, path: "../../../telemetry_reporter"},

      # ML/Tokenization
      {:nx, "~> 0.9"},
      {:tokenizers, "~> 0.5"},
      {:tiktoken_ex, path: "../../../../North-Shore-AI/tiktoken_ex"},

      # Testing
      {:mox, "~> 1.1", only: :test},
      {:bypass, "~> 2.1", only: :test},
      {:excoveralls, "~> 0.18", only: :test}
    ]
  end
end
```

### 0.4 Create .gitignore

Create `examples/tinkex/.gitignore`:

```
# Build artifacts
/_build/
/deps/
/.fetch
erl_crash.dump
*.ez
*.beam

# Generated files
/doc/
/cover/

# Test artifacts
/tmp/

# IDE
.idea/
*.swp
*.swo
.vscode/

# OS
.DS_Store
Thumbs.db
```

### 0.5 Set Up Test Infrastructure

Create `examples/tinkex/test/test_helper.exs`:

```elixir
# Configure Logger for test output capture
Logger.configure(level: :debug)

# Start ExUnit with supertester configuration
ExUnit.start(capture_log: true, exclude: [:integration, :slow])

# Supertester handles isolation - no manual Mox setup needed
```

Create `examples/tinkex/test/support/test_helpers.ex`:

```elixir
defmodule Tinkex.TestHelpers do
  @moduledoc "Shared test utilities"

  def fixture_path(name) do
    Path.join([__DIR__, "..", "fixtures", name])
  end

  def load_fixture(name) do
    name |> fixture_path() |> File.read!()
  end

  def json_fixture(name) do
    name |> load_fixture() |> Jason.decode!()
  end
end
```

### 0.6 Verify Setup

```bash
cd examples/tinkex
mix deps.get
mix compile
mix test
```

### Test Strategy (Phase 0)

- Verify `mix new` scaffold compiles
- Verify pristine dependency resolves
- Verify test helper loads without errors
- Verify Mox mock definitions work

**Estimated Time**: 1 day

---

### Test Infrastructure Standards (MANDATORY)

**ALL tests MUST use supertester.** This is not optional. Test isolation issues are bugs that must be fixed.

#### Supertester Requirements

1. Every test module uses `Supertester.ExUnitFoundation` with `isolation: :full_isolation`
2. Zero `Process.sleep/1` - use `cast_and_sync/2` and `wait_for_*` helpers
3. All OTP processes started via `setup_isolated_genserver/3` or `setup_isolated_supervisor/3`
4. All tests MUST pass with any random seed

#### Test Template

```elixir
defmodule Tinkex.SomeTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  import Supertester.OTPHelpers
  import Supertester.GenServerHelpers
  import Supertester.Assertions

  test "isolated test" do
    {:ok, pid} = setup_isolated_genserver(MyServer)
    :ok = cast_and_sync(pid, :work)
    assert_genserver_state(pid, &match?(%{done: true}, &1))
  end
end
```

#### Forbidden Patterns

- ❌ `Process.sleep/1`
- ❌ `async: false` due to isolation issues
- ❌ Tests depending on execution order
- ❌ Global named processes
- ❌ Ignoring test failures as "flaky" or "pre-existing"

---

## Phase 1: Pristine Extensions

**Goal**: Add missing infrastructure to Pristine core (with TDD)

### 1.1 Enhanced Error Handling

**Test Strategy (RED)**:
```elixir
# test/pristine/error_test.exs
defmodule Pristine.ErrorTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  import Supertester.Assertions

  describe "categorization" do
    test "categorizes 429 as rate_limit" do
      error = Pristine.Error.from_status(429)
      assert error.category == :rate_limit
    end

    test "categorizes 503 as service_unavailable" do
      error = Pristine.Error.from_status(503)
      assert error.category == :service_unavailable
    end

    test "extracts retry_after_ms from headers" do
      error = Pristine.Error.from_response(429, [{"retry-after", "30"}])
      assert error.retry_after_ms == 30_000
    end
  end

  describe "retryable?" do
    test "rate_limit errors are retryable" do
      assert Pristine.Error.retryable?(%{category: :rate_limit})
    end

    test "validation errors are not retryable" do
      refute Pristine.Error.retryable?(%{category: :validation})
    end
  end
end
```

**Files to modify/create**:
- `lib/pristine/error.ex` - Add category, retry_after_ms, request_id

### 1.2 Compression Support

**Test Strategy (RED)**:
```elixir
# test/pristine/compression_test.exs
defmodule Pristine.CompressionTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  import Supertester.Assertions

  describe "gzip" do
    test "compress/decompress round-trip" do
      original = "Hello, World!" |> String.duplicate(100)
      {:ok, compressed} = Pristine.Compression.Gzip.compress(original)
      {:ok, decompressed} = Pristine.Compression.Gzip.decompress(compressed)
      assert decompressed == original
    end

    test "compressed data is smaller" do
      original = "Hello, World!" |> String.duplicate(100)
      {:ok, compressed} = Pristine.Compression.Gzip.compress(original)
      assert byte_size(compressed) < byte_size(original)
    end
  end
end
```

**Files to create**:
- `lib/pristine/ports/compression.ex`
- `lib/pristine/adapters/compression/gzip.ex`
- `lib/pristine/adapters/compression/noop.ex`

### 1.3 Session Management

**Test Strategy (RED)**:
```elixir
# test/pristine/session_test.exs
defmodule Pristine.SessionTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  import Supertester.OTPHelpers
  import Supertester.GenServerHelpers
  import Supertester.Assertions

  describe "Session" do
    test "creates session with id and expiry" do
      session = Pristine.Session.new("sess_123", 3600)
      assert session.id == "sess_123"
      assert session.expires_at > DateTime.utc_now()
    end

    test "detects expired sessions" do
      session = Pristine.Session.new("sess_123", -1)
      assert Pristine.Session.expired?(session)
    end
  end

  describe "SessionManager" do
    test "schedules heartbeat" do
      {:ok, pid} = setup_isolated_genserver(Pristine.SessionManager, [
        session_id: "sess_123",
        heartbeat_interval: 100,
        heartbeat_fn: fn _ -> :ok end
      ])
      # Use wait_for_condition instead of Process.sleep
      wait_for_condition(fn -> Process.alive?(pid) end, timeout: 200)
      assert Process.alive?(pid)
    end
  end
end
```

**Files to create**:
- `lib/pristine/core/session.ex`
- `lib/pristine/core/session_manager.ex`

### 1.4 Environment Utilities

**Test Strategy (RED)**:
```elixir
# test/pristine/env_test.exs
defmodule Pristine.EnvTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  import Supertester.Assertions

  describe "get/3" do
    test "returns env var value" do
      System.put_env("TEST_VAR", "hello")
      assert Pristine.Env.get("TEST_VAR") == "hello"
    after
      System.delete_env("TEST_VAR")
    end

    test "returns default when not set" do
      assert Pristine.Env.get("NONEXISTENT", "default") == "default"
    end
  end

  describe "get_integer/3" do
    test "coerces string to integer" do
      System.put_env("TEST_INT", "42")
      assert Pristine.Env.get_integer("TEST_INT") == 42
    after
      System.delete_env("TEST_INT")
    end
  end

  describe "get_boolean/3" do
    test "coerces 'true' to true" do
      System.put_env("TEST_BOOL", "true")
      assert Pristine.Env.get_boolean("TEST_BOOL") == true
    after
      System.delete_env("TEST_BOOL")
    end
  end
end
```

**Files to create**:
- `lib/pristine/core/env.ex`

### 1.5 Verify Foundation Integration

**Test Strategy (RED)**:
```elixir
# test/pristine/foundation_integration_test.exs
defmodule Pristine.FoundationIntegrationTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  import Supertester.OTPHelpers
  import Supertester.GenServerHelpers
  import Supertester.Assertions

  describe "retry adapter" do
    test "uses Foundation.Retry under the hood" do
      # Verify Pristine.Adapters.Retry delegates to Foundation.Retry
      config = Pristine.Adapters.Retry.default_config()
      assert config.max_attempts > 0
    end
  end

  describe "circuit breaker adapter" do
    test "uses Foundation.CircuitBreaker" do
      {:ok, _pid} = setup_isolated_genserver(Pristine.Adapters.CircuitBreaker, [name: :test_cb])
      assert Pristine.Adapters.CircuitBreaker.state(:test_cb) == :closed
    end
  end
end
```

**Estimated Time**: 4-6 days (with TDD overhead)

---

## Phase 2: Tinkex Manifest

**Goal**: Define complete API in manifest format

### Test Strategy (RED)

```elixir
# examples/tinkex/test/tinkex/manifest_test.exs
defmodule Tinkex.ManifestTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  import Supertester.Assertions

  describe "load!/1" do
    test "loads manifest from file" do
      manifest = Tinkex.Manifest.load!()
      assert is_map(manifest.endpoints)
    end

    test "includes all session endpoints" do
      manifest = Tinkex.Manifest.load!()
      assert manifest.endpoints[:create_session]
      assert manifest.endpoints[:heartbeat]
    end

    test "includes all training endpoints" do
      manifest = Tinkex.Manifest.load!()
      assert manifest.endpoints[:forward_backward]
      assert manifest.endpoints[:forward_backward].async == true
      assert manifest.endpoints[:optim_step]
      assert manifest.endpoints[:save_weights]
      assert manifest.endpoints[:load_weights]
    end

    test "includes all sampling endpoints" do
      manifest = Tinkex.Manifest.load!()
      assert manifest.endpoints[:sample]
      assert manifest.endpoints[:sample_stream]
      assert manifest.endpoints[:sample_stream].streaming == true
      assert manifest.endpoints[:compute_logprobs]
    end

    test "includes all REST endpoints" do
      manifest = Tinkex.Manifest.load!()
      assert manifest.endpoints[:list_sessions]
      assert manifest.endpoints[:get_session]
      assert manifest.endpoints[:list_checkpoints]
      assert manifest.endpoints[:get_checkpoint_archive_url]
    end
  end
end
```

### 2.1 Create Full Manifest

Create `examples/tinkex/priv/manifest.exs` with all endpoints from original tinkex:

**Endpoints to define**:
- Session: create_session, heartbeat
- Service: create_model, create_sampling_session, get_server_capabilities
- Training: forward_backward, forward, optim_step, save_weights, load_weights, get_info, unload_model
- Sampling: sample, sample_stream, compute_logprobs
- Weights: save_weights_for_sampler
- Futures: retrieve_result
- REST: list_sessions, get_session, list_checkpoints, get_checkpoint_archive_url, list_training_runs, health
- Telemetry: send_telemetry

**Estimated Time**: 2-3 days (with TDD overhead)

---

## Phase 3: Tinkex Types

**Goal**: Port all ML types with validation via Sinter

### Test Strategy (RED)

```elixir
# examples/tinkex/test/tinkex/types/model_input_test.exs
defmodule Tinkex.Types.ModelInputTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  import Supertester.Assertions

  alias Tinkex.Types.ModelInput

  describe "from_ints/1" do
    test "creates model input from integer list" do
      input = ModelInput.from_ints([1, 2, 3, 4])
      assert input.tokens == [1, 2, 3, 4]
    end

    test "validates tokens are integers" do
      assert_raise Sinter.ValidationError, fn ->
        ModelInput.from_ints(["not", "integers"])
      end
    end
  end

  describe "to_map/1" do
    test "serializes for API" do
      input = ModelInput.from_ints([1, 2, 3])
      map = ModelInput.to_map(input)
      assert map["tokens"] == [1, 2, 3]
    end
  end
end
```

### 3.1 Port Type Files with Sinter Schemas

Port from `~/p/g/North-Shore-AI/tinkex/lib/tinkex/types/` to `examples/tinkex/lib/tinkex/types/`

**Type Categories (~60 files)**:

**Core Types**:
- model_input.ex
- tensor_data.ex
- tensor_dtype.ex
- datum.ex
- adam_params.ex
- loss_fn_type.ex
- lora_config.ex

**Sampling Types**:
- sampling_params.ex
- sampled_sequence.ex
- sample_stream_chunk.ex
- stop_reason.ex

**Training Types**:
- forward_backward_input.ex
- forward_backward_output.ex
- forward_backward_request.ex
- optim_step_request.ex
- optim_step_response.ex
- custom_loss_output.ex
- regularizer_spec.ex
- regularizer_output.ex

**Session/Model Types**:
- create_session_request.ex
- create_session_response.ex
- create_model_request.ex
- create_model_response.ex
- create_sampling_session_request.ex
- create_sampling_session_response.ex
- model_data.ex
- queue_state.ex

**Checkpoint Types**:
- checkpoint.ex
- checkpoints_list_response.ex
- parsed_checkpoint_tinker_path.ex

**Weight Types**:
- save_weights_request.ex
- save_weights_response.ex
- load_weights_request.ex
- load_weights_response.ex
- weights_info_response.ex
- save_weights_for_sampler_request.ex
- save_weights_for_sampler_response.ex

**REST Types**:
- list_sessions_response.ex
- get_session_response.ex
- training_run.ex
- training_runs_response.ex
- health_response.ex
- supported_model.ex
- get_server_capabilities_response.ex
- get_sampler_response.ex

**Future Types**:
- future_retrieve_request.ex
- future_responses.ex
- try_again_response.ex

**Error Types**:
- request_error_category.ex
- request_failed_response.ex

**Telemetry Types**:
- telemetry/*.ex (9 files)

### 3.2 Schema Definition Pattern

Each type uses Sinter for validation:

```elixir
defmodule Tinkex.Types.ModelInput do
  use Sinter.Schema

  schema do
    field :tokens, {:list, :integer}, required: true
    field :cache_id, :string
  end

  def from_ints(tokens) when is_list(tokens) do
    new!(%{tokens: tokens})
  end

  def to_map(%__MODULE__{} = input) do
    %{
      "tokens" => input.tokens,
      "cache_id" => input.cache_id
    }
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end
end
```

**Estimated Time**: 2-3 days (with TDD overhead)

---

## Phase 4: Core Clients

**Goal**: Implement thin client wrappers using Pristine pipeline

### Test Strategy (RED)

```elixir
# examples/tinkex/test/tinkex/service_client_test.exs
defmodule Tinkex.ServiceClientTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  import Supertester.OTPHelpers
  import Supertester.GenServerHelpers
  import Supertester.Assertions
  import Supertester.MockHelpers

  describe "new/1" do
    test "creates client with API key" do
      client = Tinkex.ServiceClient.new(api_key: "test_key")
      assert client.api_key == "test_key"
    end

    test "uses env var when no key provided" do
      System.put_env("TINKEX_API_KEY", "env_key")
      client = Tinkex.ServiceClient.new()
      assert client.api_key == "env_key"
    after
      System.delete_env("TINKEX_API_KEY")
    end
  end

  describe "create_session/2" do
    test "creates session and returns session_id" do
      mock_http_client = setup_isolated_mock(Tinkex.HTTPClient.Behaviour)
      expect_call(mock_http_client, :request, fn _req ->
        {:ok, %{status: 200, body: %{"session_id" => "sess_123"}}}
      end)

      client = Tinkex.ServiceClient.new(api_key: "test", http_client: mock_http_client)
      {:ok, session} = Tinkex.ServiceClient.create_session(client)
      assert session.id == "sess_123"
    end
  end

  describe "create_training_client/2" do
    test "returns TrainingClient with model_id" do
      # ... setup mocks for create_model using setup_isolated_mock ...
      training_client = Tinkex.ServiceClient.create_training_client(client, model: "llama-3")
      assert training_client.model_id == "model_123"
    end
  end
end
```

### 4.1 ServiceClient

**Implementation**:
1. Load manifest on `new/1`
2. Build Pristine.Context with adapters from foundation/sinter
3. Create session via `Pipeline.execute`
4. Factory methods for other clients

### 4.2 TrainingClient

**Implementation**:
1. Store model_id, context, manifest
2. `forward_backward/4` -> `Pipeline.execute_future`
3. `optim_step/3` -> `Pipeline.execute_future`
4. `save_state/3` -> `Pipeline.execute_future`
5. `load_state/3` -> `Pipeline.execute_future`
6. High-level `train_batch/3`

### 4.3 SamplingClient

**Implementation**:
1. Store sampler_id, context, manifest
2. `sample/4` -> `Pipeline.execute_future`
3. `sample_stream/4` -> `Pipeline.execute_stream` + `SampleStream.decode`
4. `compute_logprobs/3` -> `Pipeline.execute_future`

### 4.4 RestClient

Simple pass-through to `Pipeline.execute` for each REST endpoint.

**Estimated Time**: 4-6 days (with TDD overhead)

---

## Phase 5: Domain Features

**Goal**: Port domain-specific functionality (ML logic, not infrastructure)

### Test Strategy (RED)

```elixir
# examples/tinkex/test/tinkex/regularizer_test.exs
defmodule Tinkex.RegularizerTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  import Supertester.OTPHelpers
  import Supertester.Assertions

  describe "L2 regularizer" do
    test "computes L2 penalty" do
      weights = Nx.tensor([1.0, 2.0, 3.0])
      penalty = Tinkex.Regularizers.L2.compute(weights, lambda: 0.01)
      assert_in_delta Nx.to_number(penalty), 0.14, 0.001
    end
  end

  describe "Executor" do
    test "runs multiple regularizers in parallel" do
      specs = [
        %{type: :l2, lambda: 0.01},
        %{type: :l1, lambda: 0.001}
      ]
      weights = Nx.tensor([1.0, 2.0, 3.0])
      {:ok, results} = Tinkex.Regularizer.Executor.run(specs, weights)
      assert length(results) == 2
    end
  end
end
```

### 5.1 Regularizers

**Files to port** (domain logic only, infrastructure removed):
- `regularizer/regularizer.ex` (behaviour)
- `regularizer/executor.ex`
- `regularizer/pipeline.ex`
- `regularizer/gradient_tracker.ex`
- `regularizer/telemetry.ex`
- `regularizers/*.ex` (8 implementations: L1, L2, elastic_net, entropy, orthogonality, gradient_penalty, kl_divergence, consistency)

### 5.2 Recovery

**Files to port**:
- `recovery/policy.ex`
- `recovery/behaviours.ex`
- `recovery/monitor.ex`
- `recovery/executor.ex`

Use `Foundation.Retry` and `Foundation.CircuitBreaker` for infrastructure.

### 5.3 Streaming

**Files to port**:
- `streaming/sse_decoder.ex`

Use `Pristine.Streaming.SSEDecoder` as base, keep `SampleStreamChunk` handling.

### 5.4 Tokenization

**Files to port**:
- `tokenizer.ex`
- `tokenizer/http_client.ex`

Keep tokenizer caching via ETS, HuggingFace integration for model downloads.

### 5.5 HuggingFace Integration

**Files to port**:
- `hugging_face.ex`
- `checkpoint_download.ex`

Keep as-is (uses `:httpc`, not Pristine). Consider future Pristine integration.

### 5.6 Telemetry Types

**Files to port**:
- `telemetry/provider.ex`
- `telemetry/otel.ex`
- `telemetry/capture.ex`

Use `TelemetryReporter` for actual reporting, keep provider abstraction.

**Estimated Time**: 4-6 days (with TDD overhead)

---

## Phase 6: CLI (Optional/Separate)

**Goal**: Port CLI for checkpoint management and sampling

### Test Strategy (RED)

```elixir
# examples/tinkex/test/tinkex/cli_test.exs
defmodule Tinkex.CLITest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  import Supertester.OTPHelpers
  import Supertester.Assertions
  import Supertester.MockHelpers
  import ExUnit.CaptureIO

  describe "version command" do
    test "outputs version string" do
      output = capture_io(fn ->
        Tinkex.CLI.run(["version"])
      end)
      assert output =~ "tinkex"
    end

    test "outputs JSON with --json flag" do
      output = capture_io(fn ->
        Tinkex.CLI.run(["version", "--json"])
      end)
      assert {:ok, _} = Jason.decode(output)
    end
  end

  describe "checkpoint command" do
    test "saves checkpoint with required args" do
      # Use setup_isolated_mock for ServiceClient mocking
      mock_client = setup_isolated_mock(Tinkex.ServiceClient.Behaviour)
      expect_call(mock_client, :save_checkpoint, fn _, _ -> {:ok, %{}} end)

      output = capture_io(fn ->
        Tinkex.CLI.run(["checkpoint", "save", "--model", "test", "--name", "ckpt"])
      end)
      assert output =~ "Checkpoint saved"
    end
  end
end
```

### 6.1 CLI Structure

**Files to port**:
- `cli.ex` (main entrypoint)
- `cli/parser.ex` (argument parsing)
- `cli/formatting.ex` (output formatting)
- `cli/pagination.ex` (paginated output)
- `cli/commands/version.ex`
- `cli/commands/checkpoint.ex`
- `cli/commands/sample.ex`
- `cli/commands/run.ex`

### 6.2 Escript Configuration

Add to `examples/tinkex/mix.exs`:

```elixir
def project do
  [
    # ... existing config ...
    escript: escript()
  ]
end

defp escript do
  [
    main_module: Tinkex.CLI,
    name: "tinkex"
  ]
end
```

**Estimated Time**: 2-3 days (with TDD overhead)

---

## Phase 7: Utilities and Enhancements

**Goal**: Port remaining utilities

### 7.1 Future Combiner

**Test Strategy (RED)**:
```elixir
defmodule Tinkex.Future.CombinerTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  import Supertester.OTPHelpers
  import Supertester.Assertions

  describe "all/2" do
    test "waits for all futures" do
      {:ok, task_supervisor} = setup_isolated_supervisor(Task.Supervisor)

      futures = [
        Task.Supervisor.async(task_supervisor, fn -> {:ok, 1} end),
        Task.Supervisor.async(task_supervisor, fn -> {:ok, 2} end)
      ]
      {:ok, results} = Tinkex.Future.Combiner.all(futures)
      assert results == [1, 2]
    end
  end

  describe "race/2" do
    test "returns first completed" do
      {:ok, task_supervisor} = setup_isolated_supervisor(Task.Supervisor)

      # Use wait_for_condition instead of timer.sleep for the slow task
      futures = [
        Task.Supervisor.async(task_supervisor, fn ->
          wait_for_condition(fn -> false end, timeout: 100)
          {:ok, :slow}
        end),
        Task.Supervisor.async(task_supervisor, fn -> {:ok, :fast} end)
      ]
      {:ok, result} = Tinkex.Future.Combiner.race(futures)
      assert result == :fast
    end
  end
end
```

### 7.2 Files Module

**Files to port**:
- `files/reader.ex`
- `files/async_reader.ex`
- `files/transform.ex`
- `files/types.ex`

### 7.3 Utilities

**Files to port**:
- `transform.ex` (data transformations)
- `logging.ex` (structured logging)
- `env.ex` (environment utilities)
- `version.ex` (version info)
- `metrics.ex` (metrics collection)
- `metrics_reduction.ex` (metrics aggregation)
- `byte_estimator.ex` (size estimation)
- `pool_key.ex` (connection pooling)

### 7.4 Queue Management

**Files to port**:
- `queue_state_observer.ex`
- `queue_state_logger.ex`
- `sampling_dispatch.ex`
- `sampling_registry.ex`

**Estimated Time**: 3-4 days (with TDD overhead)

---

## Phase 8: Integration Testing

### 8.1 End-to-End Tests

Test full workflows against mock server:

```elixir
# examples/tinkex/test/integration/training_workflow_test.exs
defmodule Tinkex.Integration.TrainingWorkflowTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  import Supertester.OTPHelpers
  import Supertester.Assertions

  @moduletag :integration

  setup do
    # Use supertester's isolated bypass setup
    {:ok, bypass} = setup_isolated_bypass()
    {:ok, bypass: bypass, base_url: "http://localhost:#{bypass.port}"}
  end

  test "complete training workflow", %{bypass: bypass, base_url: base_url} do
    # Setup mock responses
    Bypass.expect(bypass, "POST", "/v1/session", fn conn ->
      Plug.Conn.resp(conn, 200, ~s({"session_id": "sess_123"}))
    end)

    Bypass.expect(bypass, "POST", "/v1/model", fn conn ->
      Plug.Conn.resp(conn, 200, ~s({"model_id": "model_456"}))
    end)

    # ... more expectations ...

    # Run workflow
    client = Tinkex.ServiceClient.new(api_key: "test", base_url: base_url)
    {:ok, session} = Tinkex.ServiceClient.create_session(client)
    {:ok, training} = Tinkex.ServiceClient.create_training_client(client, model: "llama-3")
    {:ok, _} = Tinkex.TrainingClient.forward_backward(training, batch)
    {:ok, _} = Tinkex.TrainingClient.optim_step(training)
    {:ok, _} = Tinkex.TrainingClient.save_state(training, "checkpoint_1")
  end
end
```

### 8.2 Compatibility Tests

Verify API compatibility with original tinkex:
- Same function signatures
- Same return types
- Same error handling

### 8.3 Performance Tests

Compare with original:
- Request latency
- Memory usage
- Concurrency handling

**Estimated Time**: 3-4 days (with TDD overhead)

---

## Phase 9: Documentation

### 9.1 Update README

- New architecture overview
- Installation (as standalone or within Pristine)
- Quick start examples

### 9.2 API Documentation

- ExDoc for all public modules
- Usage examples

### 9.3 Migration Guide

For users of original tinkex:
- Breaking changes
- New patterns
- Upgrade path

**Estimated Time**: 2 days

---

## Complete File Coverage

### Original Tinkex Files (179 total)

**Infrastructure (to DELETE - replaced by deps)**:
- `retry.ex`, `retry_handler.ex`, `retry_config.ex` -> Foundation.Retry
- `circuit_breaker.ex`, `circuit_breaker/registry.ex` -> Foundation.CircuitBreaker
- `rate_limiter.ex`, `bytes_semaphore.ex`, `retry_semaphore.ex` -> Foundation.Semaphore
- `not_given.ex` -> Sinter.NotGiven
- `multipart/*.ex` -> Multipart
- `telemetry/reporter.ex`, `telemetry/reporter/*.ex` -> TelemetryReporter

**API Layer (to PORT with Pristine)**:
- `api/*.ex` (20 files) -> Manifest + Pipeline
- `http_client.ex` -> Pristine.Adapters.Finch

**Domain Logic (to PORT as-is)**:
- `types/*.ex` (~60 files)
- `regularizer/*.ex` (5 files)
- `regularizers/*.ex` (8 files)
- `recovery/*.ex` (4 files)
- `streaming/*.ex` (1 file)
- `training/*.ex` (1 file)
- `training_client/*.ex` (5 files)

**Core Clients (to REWRITE)**:
- `service_client.ex`
- `training_client.ex`
- `sampling_client.ex`
- `rest_client.ex`

**Utilities (to PORT)**:
- `tokenizer.ex`, `tokenizer/*.ex`
- `hugging_face.ex`
- `checkpoint_download.ex`
- `future.ex`, `future/*.ex`
- `files/*.ex`
- `telemetry.ex`, `telemetry/provider.ex`, `telemetry/otel.ex`, `telemetry/capture.ex`
- `transform.ex`, `logging.ex`, `env.ex`, `version.ex`
- `metrics.ex`, `metrics_reduction.ex`, `byte_estimator.ex`, `pool_key.ex`
- `queue_state_observer.ex`, `queue_state_logger.ex`
- `sampling_dispatch.ex`, `sampling_registry.ex`
- `config.ex`, `application.ex`, `error.ex`

**CLI (Optional)**:
- `cli.ex`, `cli/*.ex` (7 files)

---

## Timeline Estimate (with TDD)

| Phase | Base Effort | TDD Overhead | Total | Dependencies |
|-------|-------------|--------------|-------|--------------|
| Phase 0: Project Setup | 0.5 day | 0.5 day | **1 day** | - |
| Phase 1: Pristine Extensions | 3 days | 2 days | **5 days** | - |
| Phase 2: Manifest | 1.5 days | 1 day | **2.5 days** | Phase 1 |
| Phase 3: Types | 1.5 days | 1 day | **2.5 days** | - |
| Phase 4: Core Clients | 3 days | 2 days | **5 days** | Phase 1, 2, 3 |
| Phase 5: Domain Features | 3 days | 2 days | **5 days** | Phase 4 |
| Phase 6: CLI (Optional) | 1.5 days | 1 day | **2.5 days** | Phase 4 |
| Phase 7: Utilities | 2 days | 1.5 days | **3.5 days** | Phase 4 |
| Phase 8: Integration Testing | 2 days | 1.5 days | **3.5 days** | Phase 5, 6, 7 |
| Phase 9: Documentation | 2 days | - | **2 days** | Phase 8 |
| **Total** | **20 days** | **12.5 days** | **~32.5 days** | |

**Calendar Time**: ~6-7 weeks (accounting for parallelization)

---

## Risk Mitigation

### Risk: Pristine Pipeline Gaps

**Mitigation**: Phase 1 addresses known gaps. If more discovered, add to backlog.

### Risk: Type Compatibility

**Mitigation**: Port types first (Phase 3), test thoroughly before clients.

### Risk: TDD Slows Progress

**Mitigation**: TDD upfront investment pays off in fewer bugs and easier refactoring.

### Risk: Foundation/Sinter API Changes

**Mitigation**: Pin dependency versions, coordinate with upstream.

### Risk: Async/Polling Differences

**Mitigation**: Verify Pristine.Adapters.Future.Polling matches tinkex behavior.

### Risk: Streaming Issues

**Mitigation**: SSEDecoder already exists and is tested.

---

## Success Criteria

1. **All original functionality covered** (179 files -> fewer, using deps)
2. **100% test coverage** on new code
3. **All tests pass** (unit, integration)
4. **LOC reduction**: 15,000 -> 4,000 (~73% reduction)
5. **No infrastructure duplication**: Zero overlap with Pristine/deps
6. **API compatibility**: Same public interface as original
7. **Performance parity**: No regression in benchmarks

---

## Rollback Plan

If migration fails:
1. Keep original tinkex in `~/p/g/North-Shore-AI/tinkex`
2. examples/tinkex can be deleted and restarted
3. Pristine extensions remain useful for other SDKs
