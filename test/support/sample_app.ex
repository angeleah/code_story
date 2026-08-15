defmodule CodeStory.TestSupport.SampleApp do
  @moduledoc false

  def add_sub_mult(num1, num2) do
    num1
    |> add(num2)
    |> subtract(1)
    |> mult(5)
  end

  def add(num1, num2), do: num1 + num2

  def subtract(num1, num2), do: num1 - num2

  def mult(num1, num2), do: num1 * num2

  def divide(num1, num2), do: div(num1, num2)

  def do_stuff(num1, num2) do
    number = num1 * num2
    number_2 = divide(number, num1)
    "hello #{number_2}"
  end

  def recursive_countdown(0), do: :done
  def recursive_countdown(n), do: recursive_countdown(n - 1)

  def process_data(data), do: data

  # Calls `add/2` three times as consecutive siblings — a repeated-sibling run
  # that `CodeStory.Fold` collapses (unlike `recursive_countdown`, which nests).
  def repeat_add(x) do
    [add(x, x), add(x, x), add(x, x)]
  end

  # Entry that crosses into a boundary module (FakeRepo duck-types an Ecto repo).
  def fetch_via_repo(id) do
    CodeStory.TestSupport.FakeRepo.get(id)
  end

  # Public entry delegating to a private helper — verifies that defp
  # functions appear in traces.
  def describe_number(n) do
    classify(n)
  end

  defp classify(n) when n >= 0, do: {:non_negative, n}
  defp classify(n), do: {:negative, n}
end
