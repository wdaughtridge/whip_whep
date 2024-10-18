defmodule WhipWhep.Router do
  use Plug.Router

  require Logger

  plug Plug.Logger
  plug Plug.Static, at: "/", from: :whip_whep
  plug :match
  plug :dispatch

  post "/whip/:stream_id" do
    {:ok, offer_sdp, conn} = Plug.Conn.read_body(conn)
    offer = %ExWebRTC.SessionDescription{type: :offer, sdp: offer_sdp}
    client_id = WhipWhep.Handler.get_client_id()

    {:ok, answer, _pc} = WhipWhep.Handler.handshake(offer, :recvonly, stream_id, client_id)

    conn
    |> put_resp_header("location", "/resource/#{stream_id}")
    |> put_resp_header("client-id", client_id)
    |> put_resp_content_type("application/sdp")
    |> resp(201, answer.sdp)
    |> send_resp()
  end

  post "/whep" do
    stream_id = Plug.Conn.get_req_header(conn, "stream-id")
    client_id = WhipWhep.Handler.get_client_id()

    {:ok, offer_sdp, conn} = Plug.Conn.read_body(conn)
    offer = %ExWebRTC.SessionDescription{type: :offer, sdp: offer_sdp}

    {:ok, answer, _pc} = WhipWhep.Handler.handshake(offer, :sendonly, stream_id, client_id)

    conn
    |> put_resp_header("location", "/resource/#{stream_id}")
    |> put_resp_header("client-id", client_id)
    |> put_resp_content_type("application/sdp")
    |> resp(201, answer.sdp)
    |> send_resp()
  end

  patch "/resource/:resource_id" do
    [client_id | _] = Plug.Conn.get_req_header(conn, "client-id")

    case get_body(conn, "application/trickle-ice-sdpfrag") do
      {:ok, body, conn} ->
        candidate =
          body
          |> Jason.decode!()
          |> ExWebRTC.ICECandidate.from_json()

        Phoenix.PubSub.broadcast(WhipWhep.PubSub, client_id, {:ice_candidate, candidate})

        resp(conn, 204, "")

      {:error, _res} ->
        resp(conn, 400, "Bad request")
    end
    |> send_resp()
  end

  get "/ws" do
    WebSockAdapter.upgrade(conn, WhipWhep.Handler, %{}, [])
  end

  match _ do
    resp(conn, 404, "Not Found")
    |> send_resp()
  end

  defp get_body(conn, content_type) do
    with [^content_type] <- get_req_header(conn, "content-type"),
         {:ok, body, conn} <- read_body(conn) do
      {:ok, body, conn}
    else
      headers when is_list(headers) -> {:error, :unsupported_media}
      _other -> {:error, :bad_request}
    end
  end
end
