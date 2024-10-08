defmodule OpenAiClientTest do
  @moduledoc false

  use ExUnit.Case, async: true

  defmodule MockBreaker do
    @moduledoc false

    def call(function, args, opts) do
      send(self(), {:mock_breaker_called, function, args, opts})
      apply(function, args)
    end
  end

  setup do
    bypass = Bypass.open()

    {:ok, bypass: bypass}
  end

  defp endpoint_url(bypass) do
    "http://localhost:#{bypass.port}"
  end

  describe "post/2" do
    test "makes a post request to /foo with JSON request and response bodies", %{
      bypass: bypass
    } do
      Bypass.expect_once(bypass, "POST", "/foo", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert body == Jason.encode!(%{foo: "foo"})

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(201, Jason.encode!(%{bar: "bar"}))
      end)

      {:ok, response} =
        OpenAiClient.post("/foo",
          json: %{foo: "foo"},
          base_url: endpoint_url(bypass),
          breaker: MockBreaker
        )

      assert response.status == 201
      assert response.body == %{"bar" => "bar"}
    end

    test "adds the openai api key as a bearer token in the authorization header", %{
      bypass: bypass
    } do
      api_key = Application.get_env(:open_ai_client, :openai_api_key)

      Bypass.expect_once(bypass, "POST", "/foo", fn conn ->
        assert {"authorization", "Bearer #{api_key}"} in conn.req_headers

        Plug.Conn.resp(conn, 201, "")
      end)

      {:ok, _response} =
        OpenAiClient.post("/foo", base_url: endpoint_url(bypass), breaker: MockBreaker)
    end

    test "adds the openai-beta request header", %{
      bypass: bypass
    } do
      Bypass.expect_once(bypass, "POST", "/foo", fn conn ->
        assert {"openai-beta", "assistants=v2"} in conn.req_headers

        Plug.Conn.resp(conn, 201, "")
      end)

      {:ok, _response} =
        OpenAiClient.post("/foo",
          base_url: endpoint_url(bypass),
          breaker: MockBreaker
        )
    end

    test "MockBreaker is called with the expected arguments", %{
      bypass: bypass
    } do
      Bypass.expect_once(bypass, "POST", "/foo", fn conn ->
        Plug.Conn.resp(conn, 201, "")
      end)

      {:ok, _response} =
        OpenAiClient.post("/foo",
          base_url: endpoint_url(bypass),
          breaker: MockBreaker
        )

      expected_function = &OpenAiClient.__do_request__/3
      expected_args = [:post, "/foo", [base_url: endpoint_url(bypass)]]

      assert_receive {:mock_breaker_called, ^expected_function, ^expected_args, breaker_opts}
      assert breaker_opts[:threshold] == 10
      assert breaker_opts[:timeout_sec] == 120
      assert is_function(breaker_opts[:match_return], 1)
    end
  end

  describe "get/2" do
    test "makes a get request to /foo with JSON response body", %{
      bypass: bypass
    } do
      Bypass.expect_once(bypass, "GET", "/foo", fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{bar: "bar"}))
      end)

      {:ok, response} =
        OpenAiClient.get("/foo", base_url: endpoint_url(bypass), breaker: MockBreaker)

      assert response.status == 200
      assert response.body == %{"bar" => "bar"}
    end

    test "adds the openai api key as a bearer token in the authorization header", %{
      bypass: bypass
    } do
      api_key = Application.get_env(:open_ai_client, :openai_api_key)

      Bypass.expect_once(bypass, "GET", "/foo", fn conn ->
        assert {"authorization", "Bearer #{api_key}"} in conn.req_headers

        Plug.Conn.resp(conn, 200, "")
      end)

      {:ok, _response} =
        OpenAiClient.get("/foo", base_url: endpoint_url(bypass), breaker: MockBreaker)
    end

    test "retries the request on a 408, 429, 500, 502, 503, or 504 http status response", %{
      bypass: bypass
    } do
      retry_statuses = [408, 429, 500, 502, 503, 504]
      {:ok, _pid} = Agent.start_link(fn -> 0 end, name: :retry_counter)

      Enum.each(retry_statuses, fn status ->
        Bypass.expect(bypass, "GET", "/foo", fn conn ->
          Agent.update(:retry_counter, &(&1 + 1))
          Plug.Conn.resp(conn, status, "")
        end)

        assert {:ok, %{status: ^status}} =
                 OpenAiClient.get("/foo",
                   base_url: endpoint_url(bypass),
                   retry_delay: 0,
                   retry_log_level: false,
                   breaker: MockBreaker
                 )

        assert Agent.get_and_update(:retry_counter, fn value -> {value, 0} end) == 4
      end)
    end

    test "MockBreaker is called with the expected arguments", %{
      bypass: bypass
    } do
      Bypass.expect_once(bypass, "GET", "/foo", fn conn ->
        Plug.Conn.resp(conn, 200, "")
      end)

      {:ok, _response} =
        OpenAiClient.get("/foo",
          base_url: endpoint_url(bypass),
          breaker: MockBreaker
        )

      expected_function = &OpenAiClient.__do_request__/3
      expected_args = [:get, "/foo", [base_url: endpoint_url(bypass)]]

      assert_receive {:mock_breaker_called, ^expected_function, ^expected_args, breaker_opts}
      assert breaker_opts[:threshold] == 10
      assert breaker_opts[:timeout_sec] == 120
      assert is_function(breaker_opts[:match_return], 1)
    end
  end
end
