defmodule CodeStory.RepoParamsTest do
  use ExUnit.Case, async: true

  alias CodeStory.RepoParams

  test "read callbacks → queryable + their specific second arg" do
    assert RepoParams.names(:get) == ["queryable", "id", "opts"]
    assert RepoParams.names(:get!) == ["queryable", "id", "opts"]
    assert RepoParams.names(:get_by) == ["queryable", "filters", "opts"]
    assert RepoParams.names(:get_by!) == ["queryable", "filters", "opts"]
    assert RepoParams.names(:all) == ["queryable", "opts"]
    assert RepoParams.names(:one) == ["queryable", "opts"]
    assert RepoParams.names(:one!) == ["queryable", "opts"]
  end

  test "write callbacks → changeset" do
    for f <- [:insert, :insert!, :update, :update!, :delete, :delete!] do
      assert RepoParams.names(f) == ["changeset", "opts"]
    end
  end

  test "preload → struct + preloads" do
    assert RepoParams.names(:preload) == ["struct", "preloads", "opts"]
  end

  test "aggregate → queryable + aggregate + field" do
    assert RepoParams.names(:aggregate) == ["queryable", "aggregate", "field", "opts"]
  end

  test "unmapped functions → nil" do
    assert RepoParams.names(:insert_all) == nil
    assert RepoParams.names(:exists?) == nil
    assert RepoParams.names(:some_custom_fn) == nil
  end
end
