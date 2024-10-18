defmodule WhipWhep.Handler do
  @behaviour WebSock

  require Logger

  alias ExWebRTC.PeerConnection
  alias ExWebRTC

  @audio_codecs [
    %ExWebRTC.RTPCodecParameters{
      payload_type: 111,
      mime_type: "audio/opus",
      clock_rate: 48_000,
      channels: 2
    }
  ]

  @video_codecs [
    %ExWebRTC.RTPCodecParameters{
      payload_type: 96,
      mime_type: "video/H264",
      clock_rate: 90_000
    }
  ]

  @opts [
    ice_servers: [%{urls: "stun:stun.l.google.com:19302"}],
    audio_codecs: @audio_codecs,
    video_codecs: @video_codecs
  ]

  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 500
    }
  end

  @impl true
  def init(args) do
    pc = args[:pc]
    direction = args[:direction]
    stream_id = args[:stream_id]
    client_id = args[:client_id]

    case pc do
      nil -> 
        {:ok, %{}} 

      _ ->
        ExWebRTC.PeerConnection.controlling_process(pc, self())

        state = case direction do
          :recvonly ->
            Phoenix.PubSub.subscribe(WhipWhep.PubSub, "#{stream_id}_input")
            Phoenix.PubSub.subscribe(WhipWhep.PubSub, client_id)
            
            {audio_track_id, video_track_id} = get_tracks(pc, :receiver)
            Logger.info("Added tracks #{audio_track_id}, #{video_track_id}")

            %{stream_id: stream_id, input_pc: pc, audio_input: audio_track_id, video_input: video_track_id}

          :sendonly ->
            Phoenix.PubSub.subscribe(WhipWhep.PubSub, "#{stream_id}_output")

            {audio_track_id, video_track_id} = get_tracks(pc, :sender)
            Logger.info("Added tracks #{audio_track_id}, #{video_track_id}")

            %{stream_id: stream_id, output_pc: pc, audio_output: audio_track_id, video_output: video_track_id}
        end

        {:ok, state}
    end
  end

  @impl true
  def handle_in({msg, [opcode: :text]}, state) do
    msg
    |> Jason.decode!()
    |> handle_ws_msg(state)
  end

  @impl true
  def terminate(reason, _state) do
    Logger.info("WebSocket connection was terminated, reason: #{inspect(reason)}")
  end

  @impl true
  def handle_info({:ice_candidate, candidate}, %{output_pc: output_pc} = state) do
    ExWebRTC.PeerConnection.add_ice_candidate(output_pc, candidate)

    {:noreply, state}
  end

  @impl true
  def handle_info({:ex_webrtc, pc, {:connection_state_change, :connected}}, state) do
    Logger.info("#{inspect(pc)} is connected")

    {:noreply, state}
  end

  @impl true
  def handle_info({:ex_webrtc, pc, {:connection_state_change, :connecting}}, state) do
    Logger.info("#{inspect(pc)} is connecting")

    {:noreply, state}
  end

  @impl true
  def handle_info({:ex_webrtc, pc, {:ice_connection_state_change, :checking}}, state) do
    Logger.info("ICE #{inspect(pc)} is checking")

    {:noreply, state}
  end

  @impl true
  def handle_info({:ex_webrtc, pc, {:ice_connection_state_change, :connected}}, state) do
    Logger.info("ICE #{inspect(pc)} is connected")

    {:noreply, state}
  end

  @impl true
  def handle_info({:ex_webrtc, pc, {:ice_connection_state_change, :completed}}, state) do
    Logger.info("ICE #{inspect(pc)} is completed")

    {:noreply, state}
  end

  @impl true
  def handle_info({:ex_webrtc, _pc, {:ice_candidate, candidate}}, state) do
    Logger.info("ICE candidate #{inspect(candidate)} received")

    {:noreply, state}
  end

  @impl true
  def handle_info({:ex_webrtc, input_pc, {:rtp, id, nil, packet}}, %{stream_id: stream_id, input_pc: input_pc, audio_input: id} = state) do
    Phoenix.PubSub.broadcast(WhipWhep.PubSub, "#{stream_id}_output", {:rtp_audio, packet})

    {:noreply, state}
  end

  @impl true
  def handle_info({:ex_webrtc, input_pc, {:rtp, id, nil, packet}}, %{stream_id: stream_id, input_pc: input_pc, video_input: id} = state) do
    Phoenix.PubSub.broadcast(WhipWhep.PubSub, "#{stream_id}_output", {:rtp_video, packet})

    {:noreply, state}
  end

  @impl true
  def handle_info({:rtp_audio, packet}, %{output_pc: output_pc, audio_output: id} = state) do
    ExWebRTC.PeerConnection.send_rtp(output_pc, id, packet) 

    {:noreply, state}
  end

  @impl true
  def handle_info({:rtp_video, packet}, %{output_pc: output_pc, video_output: id} = state) do
    ExWebRTC.PeerConnection.send_rtp(output_pc, id, packet) 

    {:noreply, state}
  end

  @impl true
  def handle_info({:ex_webrtc, _pc, {:rtcp, packets}}, state) do
    for packet <- packets do
      case packet do
        {_track_id, %ExRTCP.Packet.PayloadFeedback.PLI{}} when state.input_pc != nil ->
          :ok = ExWebRTC.PeerConnection.send_pli(state.input_pc, state.video_input)

        _other ->
          :ok
      end
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.info("Got unhandled msg #{inspect(msg)}")

    {:noreply, state}
  end

  def handshake(offer, direction, stream_id, client_id) do
    pc_opts = Keyword.put(@opts, :controlling_process, self())

    child_spec = %{
      id: PeerConnection,
      start: {ExWebRTC.PeerConnection, :start_link, [pc_opts]},
      restart: :temporary
    }

    {:ok, pc} = DynamicSupervisor.start_child(
      {:via, PartitionSupervisor, {WhipWhep.DynamicSupervisors, self()}},
      child_spec
    )
    :ok = ExWebRTC.PeerConnection.set_remote_description(pc, offer)

    if direction == :sendonly do
      stream_id = ExWebRTC.MediaStreamTrack.generate_stream_id()
      {:ok, _sender} = ExWebRTC.PeerConnection.add_track(pc, ExWebRTC.MediaStreamTrack.new(:audio, [stream_id]))
      {:ok, _sender} = ExWebRTC.PeerConnection.add_track(pc, ExWebRTC.MediaStreamTrack.new(:video, [stream_id]))
    end

    transceivers = ExWebRTC.PeerConnection.get_transceivers(pc)

    for %{id: id} <- transceivers do
      ExWebRTC.PeerConnection.set_transceiver_direction(pc, id, direction)
    end

    {:ok, answer} = ExWebRTC.PeerConnection.create_answer(pc)
    :ok = ExWebRTC.PeerConnection.set_local_description(pc, answer)

    receive do
      {:ex_webrtc, ^pc, {:ice_gathering_state_change, :complete}} -> :ok
    after
      1000 ->
        Logger.error("Timeout on ICE gathering")
        {:error, :timeout}
    end

    answer = ExWebRTC.PeerConnection.get_local_description(pc)

    Logger.info("#{answer.sdp}")

    {:ok, _} = DynamicSupervisor.start_child(
      {:via, PartitionSupervisor, {WhipWhep.DynamicSupervisors, self()}},
      {WhipWhep.Handler, [pc: pc, direction: direction, stream_id: stream_id, client_id: client_id]}
    )

    {:ok, answer, pc}
  end

  def get_client_id(), do: for(_ <- 1..10, into: "", do: <<Enum.random(~c"0123456789abcdef")>>)

  defp handle_ws_msg(%{"type" => "offer", "data" => data}, state) do
    stream_id = "12345"
    client_id = get_client_id()

    Logger.info("WS offer:\n#{data["sdp"]}")

    offer = ExWebRTC.SessionDescription.from_json(data)

    {:ok, answer, pc} = WhipWhep.Handler.handshake(offer, :sendonly, stream_id, client_id)

    ExWebRTC.PeerConnection.controlling_process(pc, self())

    Phoenix.PubSub.subscribe(WhipWhep.PubSub, "#{stream_id}_output")
    Phoenix.PubSub.subscribe(WhipWhep.PubSub, client_id)

    {audio_track_id, video_track_id} = get_tracks(pc, :sender)
    Logger.info("Added tracks #{audio_track_id}, #{video_track_id}")
    state = %{state | stream_id: stream_id, output_pc: pc, audio_output: audio_track_id, video_output: video_track_id}

    answer_json = ExWebRTC.SessionDescription.to_json(answer)

    msg =
      %{"type" => "answer", "data" => answer_json}
      |> Jason.encode!()

    Logger.info("WS answer:\n#{answer_json["sdp"]}")

    {:push, {:text, msg}, state}
  end

  defp handle_ws_msg(%{"type" => "ice", "data" => data}, state) do
    Logger.info("WS ICE candidate: #{data["candidate"]}")

    candidate = ExWebRTC.ICECandidate.from_json(data)

    :ok = ExWebRTC.PeerConnection.add_ice_candidate(state.peer_connection, candidate)

    {:ok, state}
  end

  defp get_tracks(pc, type) do
    transceivers = ExWebRTC.PeerConnection.get_transceivers(pc)
    audio_transceiver = Enum.find(transceivers, fn tr -> tr.kind == :audio end)
    video_transceiver = Enum.find(transceivers, fn tr -> tr.kind == :video end)

    audio_track_id = Map.fetch!(audio_transceiver, type).track.id
    video_track_id = Map.fetch!(video_transceiver, type).track.id

    {audio_track_id, video_track_id}
  end
end
