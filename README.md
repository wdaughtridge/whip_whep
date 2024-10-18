# Whip Whep

This is a fully distributed WebRTC streaming service!

You can run an instance of this app on many server nodes, and then 
when you stream to ONE of the instances on a /whip endpoint, ALL of
the instances can receive the video feed! That means you can scale
this "as much" as you want. I have not tested its limit, though :).

## Install Erlang/OTP 27

https://www.erlang.org/downloads

## Install Elixir 17

https://elixir-lang.org/install.html

## Build

```shell
mix deps.get
mix compile
```

## Run

```shell
iex -S mix
```

## Run distributed

### On first server:
```shell
iex --name whip_whep_1 --cookie secret_cookie -S mix
```

### On second server:
```shell
iex --name whip_whep_2 --cookie secret_cookie -S mix
```

### On nth server:
```shell
iex --name whip_whep_n --cookie secret_cookie -S mix
```

### Connect nodes:
#### Do this for each instance on each node to form a full mesh
```elixir
Node.connect(:"whip_whep_...@put.server.fqdn.here")
```

### Profit

# Stream

Use OBS Studio to stream a feed up to the media server.
On your OBS settings, set the Stream service to 'WHIP' and
the server URL to something like `http://server.fqdn.com:5296/whip/12345`.
The last part of the URL is the stream ID, i.e., the '12345' part.
Put whatever you want in the token part - there is no auth for now.
Then, you can hit stream!

NOTE: If you are running this distributed, then don't
worry which node you point to - as long as the nodes
are connected, all clients will get the video feed!

# Watch your stream

In a browser, go to `http://server.fqdn.com:5296/index.html?stream_id=12345`.
You should see your stream come through on the feed!
If you are running it distributed, you can also go to any other
node that is running the application and see the stream, e.g.,
`http://server.fqdn.com:5296/index.html?stream_id=12345`!

