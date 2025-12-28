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
      {:endpoints, {:array, :map}, [required: true]},
      {:types, :map, [required: true]},
      {:policies, :map, [optional: true]},
      {:defaults, :map, [optional: true]}
    ])
  end
end
