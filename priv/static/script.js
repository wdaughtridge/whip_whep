const pcConfig = { iceServers: [{ urls: "stun:stun.l.google.com:19302" }] };
const videoPlayer = document.getElementById("videoPlayer");
const candidates = [];
let patchEndpoint;
let clientId;

async function sendCandidate(candidate) {
  const response = await fetch(patchEndpoint, {
    method: "PATCH",
    cache: "no-cache",
    headers: {
      "Content-Type": "application/trickle-ice-sdpfrag",
      "client-id": clientId
    },
    body: candidate
  });

  if (response.status === 204) {
    console.log("Successfully sent ICE candidate:", candidate);
  } else {
    console.error(`Failed to send ICE, status: ${response.status}, candidate:`, candidate)
  }
}

async function connect() {
  const pc = new RTCPeerConnection(pcConfig);

  pc.ontrack = event => videoPlayer.srcObject = event.streams[0];
  pc.onicegatheringstatechange = () => console.log("Gathering state change: " + pc.iceGatheringState);
  pc.onconnectionstatechange = () => console.log("Connection state change: " + pc.connectionState);
  pc.onicecandidate = event => {
    if (event.candidate == null) {
      return;
    }

    const candidate = JSON.stringify(event.candidate);
    if (patchEndpoint === undefined) {
      candidates.push(candidate);
    } else {
      sendCandidate(candidate);
    }
  }

  pc.addTransceiver("video", { direction: "recvonly" });
  pc.addTransceiver("audio", { direction: "recvonly" });

  const offer = await pc.createOffer()
  await pc.setLocalDescription(offer);

  const queryString = window.location.search;
  const urlParams = new URLSearchParams(queryString);
  const stream_id = urlParams.get('stream-id');

  const response = await fetch(`${window.location.origin}/whep`, {
    method: "POST",
    cache: "no-cache",
    headers: {
      "Accept": "application/sdp",
      "Content-Type": "application/sdp",
      "stream-id": stream_id
    },
    body: pc.localDescription.sdp
  });

  if (response.status === 201) {
    patchEndpoint = response.headers.get("location");
    clientId = response.headers.get("client-id");
    console.log("Successfully initialized WHEP connection")

  } else {
    console.error(`Failed to initialize WHEP connection, status: ${response.status}`);
    return;
  }

  for (const candidate of candidates) {
    sendCandidate(candidate);
  }

  let sdp = await response.text();
  await pc.setRemoteDescription({ type: "answer", sdp: sdp });
}

var session = null;

$( document ).ready(function(){
  var loadCastInterval = setInterval(function(){
    if (chrome.cast.isAvailable) {
      console.log('Cast has loaded.');
      clearInterval(loadCastInterval);
      initializeCastApi();
    } else {
      console.log('Unavailable');
    }
  }, 1000);
});

function initializeCastApi() {
  var applicationID = chrome.cast.media.DEFAULT_MEDIA_RECEIVER_APP_ID;
  var sessionRequest = new chrome.cast.SessionRequest(applicationID);
  var apiConfig = new chrome.cast.ApiConfig(sessionRequest,
    sessionListener,
    receiverListener);
  chrome.cast.initialize(apiConfig, onInitSuccess, onInitError);
};

function sessionListener(e) {
  session = e;
  console.log('New session');
  if (session.media.length != 0) {
    console.log('Found ' + session.media.length + ' sessions.');
  }
}
 
function receiverListener(e) {
  if( e === 'available' ) {
    console.log("Chromecast was found on the network.");
  }
  else {
    console.log("There are no Chromecasts available.");
  }
}

function onInitSuccess() {
  console.log("Initialization succeeded");
}

function onInitError() {
  console.log("Initialization failed");
}

$('#castme').click(function(){
  launchApp();
});

function launchApp() {
  console.log("Launching the Chromecast App...");
  chrome.cast.requestSession(onRequestSessionSuccess, onLaunchError);
}

function onRequestSessionSuccess(e) {
  console.log("Successfully created session: " + e.sessionId);
  session = e;
}

function onLaunchError() {
  console.log("Error connecting to the Chromecast.");
}

function onRequestSessionSuccess(e) {
  console.log("Successfully created session: " + e.sessionId);
  session = e;
  loadMedia();
}

function loadMedia() {
  if (!session) {
    console.log("No session.");
    return;
  }

  var videoSrc = document.getElementById("videoPlayer").src;
  var mediaInfo = new chrome.cast.media.MediaInfo(videoSrc);
  mediaInfo.contentType = 'video/mp4';

  var request = new chrome.cast.media.LoadRequest(mediaInfo);
  request.autoplay = true;

  session.loadMedia(request, onLoadSuccess, onLoadError);
}

function onLoadSuccess() {
  console.log('Successfully loaded video.');
}

function onLoadError() {
  console.log('Failed to load video.');
}

$('#stop').click(function(){
  stopApp();
});

function stopApp() {
  session.stop(onStopAppSuccess, onStopAppError);
}

function onStopAppSuccess() {
  console.log('Successfully stopped app.');
}

function onStopAppError() {
  console.log('Error stopping app.');
}

connect();
