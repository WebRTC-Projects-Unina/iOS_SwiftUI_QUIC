# Real-time Communication on iOS with QUIC via Network.framework

This project was developed for the "Web and Real Time Communication Systems" course at the University of Naples Federico II (A.Y. 2025/2026).

## Overview

The goal of this project is to build a real-time iOS chat application that uses QUIC as the only transport protocol, taking advantage of its native stream multiplexing to keep logically distinct communication channels (like chat messages and presence indicators) over a single connection without the overhead of multiple TCP sockets or application-level multiplexing hacks.

The system consists of two components: `SimpleQuicClient`, a SwiftUI iOS app, and `SimpleQuicServer`, a macOS Swift command-line server. Both are written entirely in Swift and rely on Apple's `Network.framework` with `NWProtocolQUIC`, which provides the API that exposes raw QUIC streams and connection-level controls on Apple platforms.

The decision to develop natively for iOS is born from a desire to explore Apple's native frameworks and gain hands-on experience with raw QUIC implementation, experimenting with its primitives and analyzing its behavior in a real-world mobile environment.

### Repository Structure

The project is split into two separate repositories that together form the complete client-server system.

`SimpleQuicClient` is the iOS SwiftUI application. It handles user interaction, manages the QUIC connection lifecycle, and renders the chat interface.

`SimpleQuicServer` is a single-file macOS Swift command-line tool. It listens for incoming QUIC connections, accepts streams from each client, maintains per-client stream registries, and broadcasts messages to all connected peers.

`ChatMessage.swift` defines the shared JSON protocol struct used by both sides. `ChatManager.swift` owns the connection logic and all stream handling. The `ViewComponents/` directory contains reusable SwiftUI views for the chat UI.

## Topics

### QUIC Transport and Stream Multiplexing

QUIC is a general-purpose transport protocol standardised in [RFC 9000](https://www.rfc-editor.org/rfc/rfc9000). Unlike TCP, QUIC runs over UDP and natively supports multiple independent bidirectional and unidirectional streams within a single connection. Each stream has its own flow control and ordering guarantees, but head-of-line blocking is eliminated at the connection level: a lost packet on one stream does not stall delivery on another.

This project uses two bidirectional streams per client connection: a `chatStream` dedicated to join and message events, and a `presenceStream` dedicated to typing indicators. Keeping these channels on separate streams means a large burst of chat messages cannot delay a presence update, and vice versa, while the connection itself remains a single QUIC tunnel with a single handshake and a single congestion controller.

The tunnel is established using `NWConnectionGroup` combined with `NWMultiplexGroup`:

```swift
let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!)
let descriptor = NWMultiplexGroup(to: endpoint)
let groupParameters = NWParameters(quic: quicOptions)
connectionGroup = NWConnectionGroup(with: descriptor, using: groupParameters)
```

Once the group is in the `.ready` state, individual streams are opened by creating a new `NWConnection` from the group:

```swift
chatStream = connectionGroup?.extract()
presenceStream = connectionGroup?.extract()
```

Each stream is then started independently and used for send/receive operations throughout the session.

### TLS 1.3 and QUIC Security

TLS 1.3 is not an optional component of QUIC, it is mandatory and integrated directly into the QUIC handshake as specified in [RFC 9001](https://www.rfc-editor.org/rfc/rfc9001). The TLS handshake messages are carried inside QUIC CRYPTO frames rather than over a separate TLS record layer, and key material derived from TLS is used to protect QUIC packets at each encryption level. This means there is no unencrypted phase at the transport layer; QUIC connections are always encrypted.

On the server side, a TLS identity is loaded from a PKCS#12 file and passed to `NWProtocolQUIC.Options`:

```swift
let identity = // ... SecIdentity loaded from .p12
let options = NWProtocolQUIC.Options(alpn: ["chat"])
options.securityProtocolOptions.setLocalIdentity(identity)
```

On the client side, certificate verification is disabled for development purposes, since the server uses a self-signed certificate:

```swift
options.securityProtocolOptions.addPreSharedKey(/* ... */)
// In development: skip certificate chain verification
sec_protocol_options_set_verify_block(
    options.securityProtocolOptions, { _, _, completionHandler in
        completionHandler(true)
    }, .main)
```

In a real case scenario, the client should validate the server certificate against a trusted root.

### JSON Message Protocol

All messages exchanged over the streams are encoded as UTF-8 JSON. The `ChatMessage` struct defines the wire format:

```swift
struct ChatMessage: Codable {
    let text: String
    let type: String
    let sender: String
}
```

The `type` field drives dispatch on both sides. A `"join"` message is sent once on the `chatStream` when the client connects, announcing the username to the server so it can be included in the sender field of broadcast messages. Subsequent `"msg"` messages carry chat content. `"presence"` messages are sent on the `presenceStream` and indicate that the sender is currently typing.

The server simply maintains two separate dictionaries to take track of all the connections:

```swift
var activeChatStreams: [UUID: NWConnection] = [:]
var activePresenceStreams: [UUID: NWConnection] = [:]
```

When a message arrives on a `chatStream`, the server deserialises it and broadcast it to all entries in `activeChatStreams` except the sender. Presence messages are sent over all `activePresenceStreams` in the same way.

### Connection Migration

One of the most interesting properties of QUIC is connection migration: a QUIC connection is identified by a connection ID rather than the four-tuple (source IP, source port, destination IP, destination port). When the underlying network path changes (for example when an iPhone switches from Wi-Fi to cellular) the QUIC connection can survive by sending subsequent packets from the new address, without a new handshake.

`Network.framework` surfaces path changes through `pathUpdateHandler` on any connection or stream belonging to the tunnel:

```swift
chatStream?.pathUpdateHandler = { newPath in
    print("Path changed: \(newPath.status), interface: \(newPath.availableInterfaces)")
    // The QUIC tunnel remains active; no reconnection is needed
}
```

This handler fires whenever the active network interface changes. Because the connection is QUIC-based, the application layer does not need to re-establish the session or re-authenticate. The stream objects remain valid and writes can continue immediately after the path update is processed. This makes QUIC particularly well-suited to mobile clients where network transitions are frequent and often happen in the background.

### The QUIC Datagram "Struggle"

I (spending a significant amount of time) tried to force the use of **QUIC Datagrams**, which would be the ideal choice for presence updates (like "user is typing" indicators). Since these updates are ephemeral and become stale quickly, unreliable and unordered delivery is a better semantic fit than a reliable stream.

However, implementing this within `Network.framework` proved to be extremely challenging. While the documentation briefly mentions QUIC datagram support via the `isDatagram` flag, the actual implementation details are sparse and poorly documented. In my tests, instead of sending true datagrams, the framework seemed to trigger a strange fallback mechanism, effectively opening a new stream for every single message sent. 

It is worth noting that **WWDC25** [introduced](https://www.youtube.com/watch?v=9mJ-mqiyhVU) an updated version of `Network.framework`. This suggests that Apple is actively refining these APIs to better support modern primitives like QUIC (and potentially WebTransport?).
For now, I’ve kept the implementation on reliable streams.


### Modern Networking: From Handlers to Declarative Async

While this project uses the established `NWConnection` approach with completion handlers, as I was mentioning the Apple ecosystem is rapidly moving toward a more **declarative style** powered by **Swift Concurrency**. 

To illustrate the difference, here is a comparison between the "standard" handler-based setup used in this project and the modern async direction they suggest with new API:

#### Current Project Style (Handler-based)
This approach requires manual state management and escaping closures to handle the connection lifecycle.

```swift
let connection = NWConnection(to: endpoint, using: params)

connection.stateUpdateHandler = { state in
    switch state {
    case .ready:
        print("Ready to communicate!")
    case .failed(let error):
        print("Connection failed: \(error)")
    default:
        break
    }
}

connection.start(queue: .main)
```

#### The Modern Direction (Declarative Configuration & Async)
The latest updates introduce a declarative way to define the protocol stack. Instead of manually configuring an `NWParameters` object, you define the layers directly within the connection's parameters, making the hierarchy of the stack explicit and readable.

```swift
let connection = NetworkConnection(
    to: .hostPort(host: "www.example.com", port: 1029),
    using: .parameters {
        TLS {
            TCP {
                IP()
                    .fragmentationEnabled(false)
            }
        }
        .constrainedPathsProhibited(true)
    }
)
```
For further information refer to the [Apple documentaion](https://developer.apple.com/documentation/Network/NetworkConnection)

### Future Work

Several improvements and extensions are within reach once the foundational QUIC infrastructure is stable:

- **QUIC datagrams for presence.** As [mentioned above](#the-quic-datagram-struggle), properly switching presence updates to unreliable QUIC datagrams remains an open problem due to the current limitations of `Network.framework`.

- **File transfer stream.** A third stream dedicated to binary file transfers could be opened on demand. Because it would be a separate QUIC stream, a large in-progress transfer would not block or delay messages on the chat or presence streams.

- **Shared Swift Package for the protocol.** Currently, the `ChatMessage` struct and message constants are duplicated in both the client and server projects. The goal is to extract them into a single shared Swift Package. This isn't just about cleaning up code; since I am defining custom message types and their specific exchange logic, this shared package will act as the official definition of my custom application-level protocol, simulating how a real-world protocol schema works.

- **Multiple chat rooms via additional streams.** The current model opens one `chatStream` per client. Supporting multiple rooms would require opening one stream per room, or multiplexing room IDs inside the existing stream. The native QUIC multiplexing in `NWMultiplexGroup` makes the per-stream approach straightforward to implement without additional framing.
