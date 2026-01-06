# Tinkex Minimal: Thin Domain Layer Specification

This document specifies what the minimal Tinkex layer should look like after proper Pristine integration.

## Design Principles

1. **No infrastructure code** - All HTTP, retry, telemetry via Pristine
2. **Manifest-driven endpoints** - API defined in manifest, not code
3. **Domain logic only** - Training loops, sampling, ML types
4. **Thin wrappers** - Clients orchestrate Pristine calls
5. **Standalone Mix app** - Has own mix.exs, can compile/test independently

---

## Standalone Mix App Setup

Tinkex lives at `examples/tinkex/` as a **standalone Mix application** that depends on Pristine via path dependency.

### Directory Structure

```
examples/tinkex/
├── mix.exs                              # Standalone mix project
├── mix.lock                             # Lock file for deps
├── .gitignore                           # Ignore build artifacts
├── .formatter.exs                       # Formatter config
├── lib/
│   ├── tinkex.ex                        # ~100 LOC - Entrypoint
│   └── tinkex/
│       ├── service_client.ex            # ~150 LOC
│       ├── training_client.ex           # ~400 LOC
│       ├── sampling_client.ex           # ~300 LOC
│       ├── rest_client.ex               # ~100 LOC
│       ├── types/                       # ~2000 LOC total
│       │   └── ... (ML types, Sinter schemas)
│       ├── regularizer.ex               # ~50 LOC
│       ├── regularizers/                # ~400 LOC total
│       │   └── ... (8 regularizers)
│       ├── recovery/                    # ~200 LOC total
│       │   └── ...
│       ├── streaming/
│       │   └── sample_stream.ex         # ~100 LOC
│       └── integrations/
│           ├── hugging_face.ex          # ~100 LOC
│           └── checkpoint_download.ex   # ~150 LOC
├── priv/
│   └── manifest.exs                     # API definition
└── test/
    ├── test_helper.exs
    └── tinkex/
        └── ...
```

**Target: ~4,000 LOC** (vs ~15,000 current)

---

## mix.exs

```elixir
defmodule Tinkex.MixProject do
  use Mix.Project

  @version "0.2.0"

  def project do
    [
      app: :tinkex,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "Tinkex",
      description: "Elixir SDK for the Tinker ML Training Platform"
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      # Core dependency - provides ALL infrastructure
      {:pristine, path: "../../"},

      # Test dependencies only
      {:mox, "~> 1.0", only: :test}
    ]
  end
end
```

**Key points:**
- `{:pristine, path: "../../"}` is the ONLY runtime dependency
- All infrastructure (HTTP, retry, telemetry, etc.) comes from Pristine
- Mox for mocking Pristine ports in tests

---

## .gitignore

```gitignore
# Build artifacts
/_build/
/deps/

# Mix lock (tracked in repo)
# /mix.lock

# Cover
/cover/

# Dialyzer
/priv/plts/
*.plt
*.plt.hash

# Crash dumps
erl_crash.dump

# Editor
.elixir_ls/
*.swp
*.swo
*~

# OS
.DS_Store
Thumbs.db
```

---

## .formatter.exs

```elixir
[
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  line_length: 100
]
```

---

## Running Tinkex Independently

```bash
cd examples/tinkex

# Fetch deps (pulls in pristine)
mix deps.get

# Compile
mix compile

# Run tests
mix test

# Format check
mix format --check-formatted

# Type check (uses pristine's dialyzer plts)
mix dialyzer
```

---

## Module Specifications

### Tinkex (Entrypoint)

```elixir
defmodule Tinkex do
  @moduledoc """
  Tinkex - Elixir SDK for the Tinker ML Training Platform.

  This is a thin domain layer on top of Pristine. All infrastructure
  (HTTP, retry, circuit breaker, telemetry, validation) comes from Pristine.
  """

  alias Tinkex.ServiceClient

  @doc "Create a new service client"
  def new(opts \\ []) do
    ServiceClient.new(opts)
  end

  @doc "Create a training client"
  defdelegate create_training_client(client, base_model, opts \\ []),
    to: ServiceClient, as: :create_training_client

  @doc "Create a sampling client"
  defdelegate create_sampling_client(client, opts \\ []),
    to: ServiceClient, as: :create_sampling_client

  @doc "Create a REST client"
  defdelegate create_rest_client(client),
    to: ServiceClient, as: :create_rest_client

  @doc "SDK version"
  def version, do: "0.2.0"
end
```

---

### ServiceClient

```elixir
defmodule Tinkex.ServiceClient do
  @moduledoc """
  Session management and client factory.

  Uses Pristine for ALL infrastructure:
  - HTTP via Pristine.Adapters.Transport.Finch
  - Retry via Pristine.Adapters.Retry.Foundation
  - Circuit breaker via Pristine.Adapters.CircuitBreaker.Foundation
  - Rate limiting via Pristine.Adapters.RateLimit.BackoffWindow
  - Telemetry via Pristine.Adapters.Telemetry.Foundation
  - Validation via Sinter (exposed through Pristine)
  """

  alias Pristine.Core.{Context, Pipeline}
  alias Tinkex.{TrainingClient, SamplingClient, RestClient}

  defstruct [:context, :manifest, :session_id, :seq_counters]

  @manifest_path "priv/manifest.exs"

  def new(opts \\ []) do
    # Load manifest - Pristine handles validation
    manifest = Pristine.Manifest.load!(@manifest_path)

    # Build context with Pristine adapters - ZERO custom infrastructure
    context = build_context(opts)

    # Create or resume session via Pristine pipeline
    session_id = ensure_session(context, manifest, opts)

    %__MODULE__{
      context: context,
      manifest: manifest,
      session_id: session_id,
      seq_counters: %{training: :atomics.new(1, []), sampling: :atomics.new(1, [])}
    }
  end

  def create_training_client(%__MODULE__{} = client, base_model, opts \\ []) do
    seq_id = next_seq(:training, client)

    # Payload is validated by Pristine/Sinter based on manifest schema
    payload = %{
      session_id: client.session_id,
      model_seq_id: seq_id,
      base_model: base_model,
      lora_config: opts[:lora_config],
      user_metadata: opts[:user_metadata]
    }

    # Pipeline.execute_future handles:
    # - Request validation (Sinter)
    # - HTTP transport (Finch)
    # - Retry with backoff (Foundation)
    # - Circuit breaker (Foundation)
    # - Telemetry events
    # - Response validation (Sinter)
    case Pipeline.execute_future(client.manifest, :create_model, payload, client.context) do
      {:ok, task} ->
        case Task.await(task) do
          {:ok, %{"model_id" => model_id}} ->
            {:ok, TrainingClient.new(model_id, client)}
          error -> error
        end
      error -> error
    end
  end

  def create_sampling_client(%__MODULE__{} = client, opts \\ []) do
    seq_id = next_seq(:sampling, client)

    payload = %{
      session_id: client.session_id,
      sampling_session_seq_id: seq_id,
      base_model: opts[:base_model],
      model_path: opts[:model_path]
    }

    case Pipeline.execute_future(client.manifest, :create_sampling_session, payload, client.context) do
      {:ok, task} ->
        case Task.await(task) do
          {:ok, %{"sampling_session_id" => sampler_id}} ->
            {:ok, SamplingClient.new(sampler_id, client)}
          error -> error
        end
      error -> error
    end
  end

  def create_rest_client(%__MODULE__{} = client) do
    {:ok, RestClient.new(client)}
  end

  # Private - Context wiring ONLY, no custom infrastructure

  defp build_context(opts) do
    # All adapters come from Pristine - Tinkex has ZERO infrastructure code
    %Context{
      base_url: opts[:base_url] || default_base_url(),
      auth: [Pristine.Adapters.Auth.Bearer.new(api_key(opts))],
      transport: Pristine.Adapters.Transport.Finch,
      stream_transport: Pristine.Adapters.Transport.FinchStream,
      serializer: Pristine.Adapters.Serializer.JSON,
      retry: Pristine.Adapters.Retry.Foundation,
      circuit_breaker: Pristine.Adapters.CircuitBreaker.Foundation,
      rate_limiter: Pristine.Adapters.RateLimit.BackoffWindow,
      telemetry: Pristine.Adapters.Telemetry.Foundation,
      future: Pristine.Adapters.Future.Polling,
      retry_opts: [max_attempts: opts[:max_retries] || 10],
      transport_opts: [timeout: opts[:timeout] || 60_000]
    }
  end

  defp ensure_session(context, manifest, opts) do
    case opts[:session_id] do
      nil ->
        payload = %{tags: opts[:tags], user_metadata: opts[:user_metadata]}
        {:ok, %{"session_id" => id}} = Pipeline.execute(manifest, :create_session, payload, context)
        id
      id -> id
    end
  end

  defp next_seq(type, client) do
    :atomics.add_get(client.seq_counters[type], 1, 1)
  end

  defp api_key(opts) do
    opts[:api_key] || System.get_env("TINKER_API_KEY") ||
      raise "api_key required"
  end

  defp default_base_url do
    System.get_env("TINKER_BASE_URL") ||
      "https://tinker.thinkingmachines.dev/services/tinker-prod"
  end
end
```

---

### TrainingClient

```elixir
defmodule Tinkex.TrainingClient do
  @moduledoc """
  Training loop orchestration.
  Domain logic for forward/backward passes, optimizer steps, checkpoints.
  """

  alias Pristine.Core.Pipeline
  alias Tinkex.Types.{Datum, AdamParams, LossFnType, ForwardBackwardOutput}

  defstruct [:model_id, :session_id, :context, :manifest, :seq_counter]

  def new(model_id, service_client) do
    %__MODULE__{
      model_id: model_id,
      session_id: service_client.session_id,
      context: service_client.context,
      manifest: service_client.manifest,
      seq_counter: :atomics.new(1, [])
    }
  end

  @doc "Execute forward-backward pass"
  def forward_backward(%__MODULE__{} = client, data, loss_fn, opts \\ []) do
    seq_id = next_seq(client)

    payload = %{
      session_id: client.session_id,
      model_id: client.model_id,
      request_seq_id: seq_id,
      data: Datum.to_list(data),
      loss_fn: LossFnType.to_string(loss_fn),
      compute_grads: opts[:compute_grads] != false
    }

    Pipeline.execute_future(
      client.manifest,
      :forward_backward,
      payload,
      client.context,
      path_params: %{model_id: client.model_id}
    )
  end

  @doc "Execute forward-backward with custom loss function"
  def forward_backward_custom(%__MODULE__{} = client, data, loss_fn, regularizers) do
    # Domain-specific: compute custom loss with regularizers
    with {:ok, fb_task} <- forward_backward(client, data, loss_fn, compute_grads: false),
         {:ok, fb_result} <- Task.await(fb_task) do
      # Apply regularizers
      reg_results = Tinkex.Regularizer.Executor.execute(regularizers, data, fb_result)
      {:ok, merge_regularizer_results(fb_result, reg_results)}
    end
  end

  @doc "Execute optimizer step"
  def optim_step(%__MODULE__{} = client, adam_params, opts \\ []) do
    payload = %{
      session_id: client.session_id,
      model_id: client.model_id,
      request_seq_id: next_seq(client),
      adam_params: AdamParams.to_map(adam_params),
      grad_clip: opts[:grad_clip]
    }

    Pipeline.execute_future(
      client.manifest,
      :optim_step,
      payload,
      client.context,
      path_params: %{model_id: client.model_id}
    )
  end

  @doc "Save checkpoint"
  def save_state(%__MODULE__{} = client, name, opts \\ []) do
    payload = %{
      session_id: client.session_id,
      model_id: client.model_id,
      request_seq_id: next_seq(client),
      name: name,
      include_optimizer: opts[:include_optimizer] || false
    }

    Pipeline.execute_future(
      client.manifest,
      :save_weights,
      payload,
      client.context,
      path_params: %{model_id: client.model_id}
    )
  end

  @doc "Load checkpoint"
  def load_state(%__MODULE__{} = client, checkpoint_path, opts \\ []) do
    payload = %{
      session_id: client.session_id,
      model_id: client.model_id,
      request_seq_id: next_seq(client),
      checkpoint_path: checkpoint_path,
      include_optimizer: opts[:include_optimizer] || false
    }

    Pipeline.execute_future(
      client.manifest,
      :load_weights,
      payload,
      client.context,
      path_params: %{model_id: client.model_id}
    )
  end

  @doc "High-level: train a batch"
  def train_batch(%__MODULE__{} = client, data, adam_params) do
    with {:ok, fb_task} <- forward_backward(client, data, :cross_entropy),
         {:ok, fb_result} <- Task.await(fb_task),
         {:ok, optim_task} <- optim_step(client, adam_params),
         {:ok, _} <- Task.await(optim_task) do
      {:ok, ForwardBackwardOutput.from_map(fb_result)}
    end
  end

  # Private

  defp next_seq(client) do
    :atomics.add_get(client.seq_counter, 1, 1)
  end

  defp merge_regularizer_results(fb_result, reg_results) do
    # Merge regularizer outputs into training result
    Map.put(fb_result, "regularizer_outputs", reg_results)
  end
end
```

---

### SamplingClient

```elixir
defmodule Tinkex.SamplingClient do
  @moduledoc """
  Text generation with streaming support.
  """

  alias Pristine.Core.Pipeline
  alias Tinkex.Types.{ModelInput, SamplingParams}
  alias Tinkex.Streaming.SampleStream

  defstruct [:sampler_id, :session_id, :context, :manifest, :seq_counter]

  def new(sampler_id, service_client) do
    %__MODULE__{
      sampler_id: sampler_id,
      session_id: service_client.session_id,
      context: service_client.context,
      manifest: service_client.manifest,
      seq_counter: :atomics.new(1, [])
    }
  end

  @doc "Generate text (async)"
  def sample(%__MODULE__{} = client, input, params, opts \\ []) do
    payload = build_sample_payload(client, input, params, opts)

    Pipeline.execute_future(
      client.manifest,
      :sample,
      payload,
      client.context,
      path_params: %{sampler_id: client.sampler_id}
    )
  end

  @doc "Generate text with streaming"
  def sample_stream(%__MODULE__{} = client, input, params, opts \\ []) do
    payload = build_sample_payload(client, input, params, opts)

    case Pipeline.execute_stream(
      client.manifest,
      :sample_stream,
      payload,
      client.context,
      path_params: %{sampler_id: client.sampler_id}
    ) do
      {:ok, stream_response} ->
        {:ok, SampleStream.decode(stream_response.stream)}
      error -> error
    end
  end

  @doc "Compute log probabilities"
  def compute_logprobs(%__MODULE__{} = client, input, opts \\ []) do
    payload = %{
      session_id: client.session_id,
      sampler_id: client.sampler_id,
      request_seq_id: next_seq(client),
      input: ModelInput.to_map(input)
    }

    Pipeline.execute_future(
      client.manifest,
      :compute_logprobs,
      payload,
      client.context,
      path_params: %{sampler_id: client.sampler_id}
    )
  end

  # Private

  defp build_sample_payload(client, input, params, opts) do
    %{
      session_id: client.session_id,
      sampler_id: client.sampler_id,
      request_seq_id: next_seq(client),
      input: ModelInput.to_map(input),
      sampling_params: SamplingParams.to_map(params),
      n: opts[:n] || 1
    }
  end

  defp next_seq(client) do
    :atomics.add_get(client.seq_counter, 1, 1)
  end
end
```

---

### RestClient

```elixir
defmodule Tinkex.RestClient do
  @moduledoc """
  Checkpoint and session management facade.
  """

  alias Pristine.Core.Pipeline

  defstruct [:session_id, :context, :manifest]

  def new(service_client) do
    %__MODULE__{
      session_id: service_client.session_id,
      context: service_client.context,
      manifest: service_client.manifest
    }
  end

  def list_checkpoints(%__MODULE__{} = client, opts \\ []) do
    Pipeline.execute(client.manifest, :list_checkpoints, %{}, client.context, query: opts)
  end

  def get_checkpoint(%__MODULE__{} = client, checkpoint_id) do
    Pipeline.execute(
      client.manifest,
      :get_checkpoint,
      %{},
      client.context,
      path_params: %{checkpoint_id: checkpoint_id}
    )
  end

  def delete_checkpoint(%__MODULE__{} = client, checkpoint_id) do
    Pipeline.execute(
      client.manifest,
      :delete_checkpoint,
      %{},
      client.context,
      path_params: %{checkpoint_id: checkpoint_id}
    )
  end

  def list_sessions(%__MODULE__{} = client, opts \\ []) do
    Pipeline.execute(client.manifest, :list_sessions, %{}, client.context, query: opts)
  end

  def get_training_run(%__MODULE__{} = client, run_id) do
    Pipeline.execute(
      client.manifest,
      :get_training_run,
      %{},
      client.context,
      path_params: %{run_id: run_id}
    )
  end

  # ... more simple pass-through methods
end
```

---

### Manifest

```elixir
# priv/manifest.exs
%{
  name: "tinkex",
  version: "0.2.0",
  base_url: "${TINKER_BASE_URL:-https://tinker.thinkingmachines.dev/services/tinker-prod}",

  auth: %{
    default: [
      %{type: "bearer", header: "Authorization", prefix: "Bearer "}
    ]
  },

  defaults: %{
    timeout: 60_000,
    retry: "default"
  },

  retry_policies: %{
    default: %{
      max_attempts: 10,
      base_delay_ms: 1000,
      max_delay_ms: 60_000,
      jitter: true
    }
  },

  endpoints: %{
    # Session
    create_session: %{
      method: :post,
      path: "/v1/sessions",
      request: "CreateSessionRequest",
      response: "CreateSessionResponse"
    },

    heartbeat: %{
      method: :post,
      path: "/v1/sessions/{session_id}/heartbeat",
      request: "HeartbeatRequest",
      response: "HeartbeatResponse"
    },

    # Model/Training
    create_model: %{
      method: :post,
      path: "/v1/models",
      request: "CreateModelRequest",
      response: "CreateModelResponse",
      async: true,
      poll_endpoint: "retrieve_result"
    },

    forward_backward: %{
      method: :post,
      path: "/v1/models/{model_id}/forward_backward",
      request: "ForwardBackwardRequest",
      response: "ForwardBackwardOutput",
      async: true,
      poll_endpoint: "retrieve_result",
      timeout: 300_000
    },

    optim_step: %{
      method: :post,
      path: "/v1/models/{model_id}/optim_step",
      request: "OptimStepRequest",
      response: "OptimStepResponse",
      async: true,
      poll_endpoint: "retrieve_result"
    },

    save_weights: %{
      method: :post,
      path: "/v1/models/{model_id}/save",
      request: "SaveWeightsRequest",
      response: "SaveWeightsResponse",
      async: true,
      poll_endpoint: "retrieve_result"
    },

    load_weights: %{
      method: :post,
      path: "/v1/models/{model_id}/load",
      request: "LoadWeightsRequest",
      response: "LoadWeightsResponse",
      async: true,
      poll_endpoint: "retrieve_result"
    },

    # Sampling
    create_sampling_session: %{
      method: :post,
      path: "/v1/samplers",
      request: "CreateSamplingSessionRequest",
      response: "CreateSamplingSessionResponse",
      async: true,
      poll_endpoint: "retrieve_result"
    },

    sample: %{
      method: :post,
      path: "/v1/samplers/{sampler_id}/sample",
      request: "SampleRequest",
      response: "SampleResponse",
      async: true,
      poll_endpoint: "retrieve_result"
    },

    sample_stream: %{
      method: :post,
      path: "/v1/samplers/{sampler_id}/sample_stream",
      request: "SampleRequest",
      streaming: true,
      stream_format: "sse"
    },

    compute_logprobs: %{
      method: :post,
      path: "/v1/samplers/{sampler_id}/logprobs",
      request: "LogprobsRequest",
      response: "LogprobsResponse",
      async: true,
      poll_endpoint: "retrieve_result"
    },

    # Futures
    retrieve_result: %{
      method: :post,
      path: "/v1/futures/retrieve",
      request: "FutureRetrieveRequest",
      response: "FutureResponse"
    },

    # REST
    list_sessions: %{method: :get, path: "/v1/sessions"},
    get_session: %{method: :get, path: "/v1/sessions/{session_id}"},
    list_checkpoints: %{method: :get, path: "/v1/checkpoints"},
    get_checkpoint: %{method: :get, path: "/v1/checkpoints/{checkpoint_id}"},
    delete_checkpoint: %{method: :delete, path: "/v1/checkpoints/{checkpoint_id}"},
    list_training_runs: %{method: :get, path: "/v1/training_runs"},
    get_training_run: %{method: :get, path: "/v1/training_runs/{run_id}"},
    get_server_capabilities: %{method: :get, path: "/v1/capabilities"}
  },

  types: %{
    # Type definitions for codegen (optional)
    # Can also define inline in endpoint request/response
  }
}
```

---

### Types with Sinter Validation

Types in Tinkex use Pristine's Sinter-based validation. Types can be:
1. **Generated** from manifest type definitions via `Pristine.Codegen.Type`
2. **Hand-written** using Sinter schemas directly

#### Generated Type Example (from manifest)

```elixir
# Generated by: Pristine.Codegen.Type.render_type_module/3
defmodule Tinkex.Types.AdamParams do
  @moduledoc """
  Adam optimizer parameters.
  """

  defstruct [:lr, :beta1, :beta2, :eps, :weight_decay]

  @type t :: %__MODULE__{
    lr: float(),
    beta1: float() | nil,
    beta2: float() | nil,
    eps: float() | nil,
    weight_decay: float() | nil
  }

  @doc "Returns the Sinter schema for this type."
  @spec schema() :: Sinter.Schema.t()
  def schema do
    Sinter.Schema.define([
      {:lr, :float, [required: true, description: "Learning rate"]},
      {:beta1, :float, [optional: true, default: 0.9]},
      {:beta2, :float, [optional: true, default: 0.999]},
      {:eps, :float, [optional: true, default: 1.0e-8]},
      {:weight_decay, :float, [optional: true, default: 0.0]}
    ])
  end

  @doc "Decode a map into an AdamParams struct."
  @spec decode(map()) :: {:ok, t()} | {:error, term()}
  def decode(data) when is_map(data) do
    with {:ok, validated} <- Sinter.Validator.validate(schema(), data) do
      {:ok, %__MODULE__{
        lr: validated["lr"],
        beta1: validated["beta1"],
        beta2: validated["beta2"],
        eps: validated["eps"],
        weight_decay: validated["weight_decay"]
      }}
    end
  end

  def decode(_), do: {:error, :invalid_input}

  @doc "Encode an AdamParams struct into a map."
  @spec encode(t()) :: map()
  def encode(%__MODULE__{} = struct) do
    %{
      "lr" => struct.lr,
      "beta1" => struct.beta1,
      "beta2" => struct.beta2,
      "eps" => struct.eps,
      "weight_decay" => struct.weight_decay
    }
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end

  @doc "Create a new AdamParams."
  @spec new(keyword() | map()) :: t()
  def new(attrs \\ [])
  def new(attrs) when is_list(attrs), do: struct(__MODULE__, attrs)
  def new(attrs) when is_map(attrs), do: from_map(attrs)

  @doc "Create from a map."
  @spec from_map(map()) :: t()
  def from_map(data) when is_map(data), do: struct(__MODULE__, atomize_keys(data))

  @doc "Convert to a map."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = struct) do
    struct |> Map.from_struct() |> Enum.reject(fn {_, v} -> is_nil(v) end) |> Map.new()
  end

  defp atomize_keys(map) do
    Map.new(map, fn
      {k, v} when is_binary(k) -> {String.to_existing_atom(k), v}
      {k, v} when is_atom(k) -> {k, v}
    end)
  rescue
    ArgumentError -> map
  end
end
```

#### Hand-written Type with Sinter (Union/Enum)

```elixir
defmodule Tinkex.Types.LossFnType do
  @moduledoc """
  Loss function type - union of allowed values.
  """

  @type t :: :cross_entropy | :mse | :custom

  @doc "Returns the Sinter type spec for this union."
  @spec schema() :: Sinter.Types.type_spec()
  def schema do
    {:union, [
      {:literal, "cross_entropy"},
      {:literal, "mse"},
      {:literal, "custom"}
    ]}
  end

  @doc "Decode a value for this type."
  @spec decode(term()) :: {:ok, t()} | {:error, term()}
  def decode(value) do
    case Sinter.Types.validate(schema(), value) do
      {:ok, validated} -> {:ok, to_atom(validated)}
      error -> error
    end
  end

  @doc "Encode a value for this type."
  @spec encode(t()) :: String.t()
  def encode(value), do: to_string(value)

  @doc "Convert string to atom."
  def to_atom("cross_entropy"), do: :cross_entropy
  def to_atom("mse"), do: :mse
  def to_atom("custom"), do: :custom
  def to_atom(atom) when is_atom(atom), do: atom

  @doc "Convert to string for API."
  def to_string(:cross_entropy), do: "cross_entropy"
  def to_string(:mse), do: "mse"
  def to_string(:custom), do: "custom"
  def to_string(s) when is_binary(s), do: s
end
```

#### Type with Nested References

```elixir
defmodule Tinkex.Types.ForwardBackwardOutput do
  @moduledoc """
  Output from forward-backward pass with nested tensor data.
  """

  alias Tinkex.Types.TensorData

  defstruct [:loss, :logits, :hidden_states, :grad_norm]

  @type t :: %__MODULE__{
    loss: float(),
    logits: TensorData.t() | nil,
    hidden_states: [TensorData.t()] | nil,
    grad_norm: float() | nil
  }

  @spec schema() :: Sinter.Schema.t()
  def schema do
    Sinter.Schema.define([
      {:loss, :float, [required: true]},
      {:logits, {:object, TensorData.schema()}, [optional: true]},
      {:hidden_states, {:array, {:object, TensorData.schema()}}, [optional: true]},
      {:grad_norm, :float, [optional: true]}
    ])
  end

  @spec decode(map()) :: {:ok, t()} | {:error, term()}
  def decode(data) when is_map(data) do
    with {:ok, validated} <- Sinter.Validator.validate(schema(), data),
         {:ok, logits} <- decode_ref(validated["logits"], TensorData),
         {:ok, hidden_states} <- decode_ref_list(validated["hidden_states"], TensorData) do
      {:ok, %__MODULE__{
        loss: validated["loss"],
        logits: logits,
        hidden_states: hidden_states,
        grad_norm: validated["grad_norm"]
      }}
    end
  end

  def decode(_), do: {:error, :invalid_input}

  @spec encode(t()) :: map()
  def encode(%__MODULE__{} = struct) do
    %{
      "loss" => struct.loss,
      "logits" => encode_ref(struct.logits, TensorData),
      "hidden_states" => encode_ref_list(struct.hidden_states, TensorData),
      "grad_norm" => struct.grad_norm
    }
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end

  # Reference helpers (generated by Pristine.Codegen.Type)
  defp decode_ref(nil, _module), do: {:ok, nil}
  defp decode_ref(value, module), do: module.decode(value)

  defp decode_ref_list(nil, _module), do: {:ok, nil}
  defp decode_ref_list(values, module) when is_list(values) do
    Enum.reduce_while(values, {:ok, []}, fn value, {:ok, acc} ->
      case decode_ref(value, module) do
        {:ok, decoded} -> {:cont, {:ok, [decoded | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, decoded} -> {:ok, Enum.reverse(decoded)}
      {:error, _} = error -> error
    end
  end

  defp encode_ref(nil, _module), do: nil
  defp encode_ref(value, module), do: module.encode(value)

  defp encode_ref_list(nil, _module), do: nil
  defp encode_ref_list(values, module), do: Enum.map(values, &encode_ref(&1, module))
end
```

---

## Testing Standards

### Supertester Integration (MANDATORY)

**ALL Tinkex tests MUST use [supertester](../../supertester) for proper test isolation.** This is non-negotiable. Zero test ordering or isolation issues are permitted.

### Test Module Pattern

```elixir
defmodule Tinkex.SomeTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  import Supertester.OTPHelpers
  import Supertester.GenServerHelpers
  import Supertester.Assertions

  test "example" do
    {:ok, server} = setup_isolated_genserver(MyServer)
    :ok = cast_and_sync(server, :work)
    assert_genserver_state(server, fn state -> state.ready end)
  end
end
```

### Test Dependency

```elixir
# examples/tinkex/mix.exs
defp deps do
  [
    {:pristine, path: "../../"},
    {:supertester, path: "../../../supertester", only: :test},
    {:mox, "~> 1.0", only: :test}
  ]
end
```

### Test Helper Configuration

```elixir
# examples/tinkex/test/test_helper.exs
Logger.configure(level: :debug)
ExUnit.start(capture_log: true)
```

### Mandatory Practices

1. **Full Isolation**: `isolation: :full_isolation` on all test modules
2. **Zero Sleep**: Use `cast_and_sync/2`, `wait_for_*` helpers
3. **Async-Safe**: All tests run with `async: true`
4. **Seed Independence**: Tests pass with any random seed
5. **OTP Helpers**: Use `setup_isolated_genserver/3` for all GenServers

### Forbidden Patterns

- ❌ `Process.sleep/1`
- ❌ `async: false` due to isolation issues
- ❌ Named processes without supertester isolation
- ❌ Tests that depend on execution order
- ❌ Calling test failures "pre-existing" or "flaky"

---

## What Stays vs What Goes

### Stays in Tinkex (~4,000 LOC)

| Category | Modules | LOC |
|----------|---------|-----|
| Entrypoint | `Tinkex`, `ServiceClient` | 250 |
| Clients | `TrainingClient`, `SamplingClient`, `RestClient` | 800 |
| Types | 60+ type modules | 2000 |
| Regularizers | behaviour + 8 implementations | 500 |
| Recovery | policy, monitor, behaviours | 200 |
| Streaming | `SampleStream` | 100 |
| Integrations | HuggingFace, CheckpointDownload | 250 |
| **Total** | | **~4,100** |

### Deleted from Tinkex (~11,000 LOC)

| Category | Modules | Reason |
|----------|---------|--------|
| API layer | `API.*` (15 modules) | → Pristine Pipeline |
| HTTP | `HTTPClient`, `API` | → Pristine Transport |
| Retry | `Retry*`, `RetryHandler` | → Pristine Retry |
| Circuit Breaker | `CircuitBreaker*` | → Pristine CircuitBreaker |
| Rate Limiting | `RateLimiter`, `*Semaphore` | → Pristine RateLimit |
| Telemetry | `Telemetry.*` (10 modules) | → Pristine Telemetry |
| Files | `Files.*` | → Pristine Files |
| Multipart | `Multipart.*` | → Pristine Multipart |
| Future | `Future`, `Future.Combiner` | → Pristine Future |
| Session | `SessionManager` | → Pristine Session |
| Utilities | `Config`, `Env`, `Error`, etc. | → Pristine Core |
| CLI | `CLI.*` (8 modules) | Deleted entirely |

---

## Summary

Tinkex as a standalone Mix app demonstrates the **ideal Pristine SDK pattern**:

### Key Characteristics

1. **Single Runtime Dependency**
   ```elixir
   {:pristine, path: "../../"}
   ```

2. **Zero Infrastructure Code**
   - No HTTP client implementation
   - No retry logic
   - No circuit breaker
   - No rate limiting
   - No telemetry infrastructure
   - No multipart encoding
   - All provided by Pristine adapters

3. **Sinter-Based Validation Throughout**
   - Request schemas defined in manifest
   - Response schemas validated automatically
   - Type modules use `Sinter.Schema.define/1`
   - Validation happens in Pristine Pipeline

4. **Domain Logic Only**
   - Training orchestration (forward/backward, optim step)
   - Sampling with streaming
   - Regularizer implementations
   - ML-specific types (tensors, loss functions, optimizers)

5. **Independently Testable**
   ```bash
   cd examples/tinkex
   mix test
   ```

### Infrastructure Flow

```
Tinkex Client Code
       ↓
ServiceClient.build_context/1 (wires Pristine adapters)
       ↓
Pristine.Core.Pipeline.execute/4
       ↓
┌─────────────────────────────────────────────────┐
│  Pristine Pipeline (all infrastructure here)   │
│  ├── Sinter validation (request)               │
│  ├── Pristine.Adapters.Transport.Finch         │
│  ├── Pristine.Adapters.Retry.Foundation        │
│  ├── Pristine.Adapters.CircuitBreaker.Foundation│
│  ├── Pristine.Adapters.RateLimit.BackoffWindow │
│  ├── Pristine.Adapters.Telemetry.Foundation    │
│  └── Sinter validation (response)              │
└─────────────────────────────────────────────────┘
       ↓
Validated Response → Tinkex Type.decode/1
```

This architecture ensures Tinkex remains a thin, focused SDK that leverages Pristine's battle-tested infrastructure while containing only domain-specific logic.
