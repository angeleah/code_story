defmodule CodeStory.TestSupport.SampleModule do
  @moduledoc false

  def add(num1, num2), do: num1 + num2

  def greet(name), do: "Hello, #{name}!"

  def no_args, do: :ok

  # Multi-clause function — first clause names should be canonical
  def process(:ok, result), do: {:success, result}
  def process(:error, reason), do: {:failure, reason}

  # Struct/map pattern match in params — like change_raffle(%Raffle{} = raffle, attrs)
  def transform(%{name: _} = record, opts), do: {record, opts}

  # Default args — like change_raffle(raffle, attrs \\ %{})
  def change(record, attrs \\ %{}), do: {record, attrs}

  # Typespec-style struct pattern — like Phoenix context functions
  defstruct [:name, :status]
  def update(%__MODULE__{} = record, attrs), do: {record, attrs}
end
