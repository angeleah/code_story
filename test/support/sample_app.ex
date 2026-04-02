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
end
