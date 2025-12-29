defmodule Pristine.Manifest.Schema do
  @moduledoc """
  Sinter schema for manifest validation.
  """

  alias Sinter.Schema

  @spec schema() :: Schema.t()
  def schema do
    Schema.define([
      {:name, :string, [required: true]},
      {:version, :string, [required: true]},
      {:base_url, :string, [optional: true]},
      {:auth, :map, [optional: true]},
      {:error_types, :map, [optional: true]},
      {:endpoints, {:array, :map}, [required: true]},
      {:types, :map, [required: true]},
      {:policies, :map, [optional: true]},
      {:retry_policies, :map, [optional: true]},
      {:rate_limits, :map, [optional: true]},
      {:resources, :map, [optional: true]},
      {:servers, :map, [optional: true]},
      {:middleware, :map, [optional: true]},
      {:defaults, :map, [optional: true]}
    ])
  end
end
