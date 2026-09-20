# Transport: WebTransport datagrams, and what that commits to

Video rides **QUIC DATAGRAM frames** -- WebTransport's unreliable mode. Input and
control ride a reliable stream on the same connection. `WebTransportPeer`
already maps exactly this: `TRANSFER_MODE_UNRELIABLE` to datagrams,
`TRANSFER_MODE_RELIABLE` to per-packet bidi streams.

## Why unreliable rather than a stream per frame

A retransmitted video frame arrives after the moment it was for. Reliability
buys nothing once the deadline has passed, and costs head-of-line blocking while
it tries. The measured fragment counts make this affordable: on the render
corpus, hardware AV1 needs 29 fragments a frame and loses 2.9% of frames at 0.1%
packet loss. A dropped frame with rolling intra refresh is a momentary artefact,
not a broken stream.

A reliable stream per frame stays the fallback for high-loss links, where 25% of
frames die at 1% loss. QUIC does not head-of-line-block across streams, so that
path is available on the same connection without a redesign.

## What QUIC provides, and what this repository must build

RFC 9221 is precise about the division, so it is quoted rather than paraphrased.
DATAGRAM frames *"employ the QUIC connection's congestion controller"*, and
*"although DATAGRAM frames are not retransmitted upon loss detection, they are
ack-eliciting"*.

Provided by the transport:

- congestion control, shared with the rest of the connection
- a per-datagram delivery-or-loss signal back to the sender
- no head-of-line blocking between frames

Owed by this repository:

- **the bitrate loop** -- turning that loss signal into an encoder target. The
  input exists; nothing consumes it yet.
- **recovery without a keyframe request.** `encode_intra_refresh` is exposed by
  both cards on this desk and is an NVENC feature, so a decoder that missed a
  frame recovers on the rolling refresh rather than by asking for an intra frame
  and waiting a round trip.
- **a jitter buffer**, absorbing arrival variance before presentation.
- **FEC**, only if the loss figures justify it. They do not at 0.1%.

Deliberately not built: retransmission. That is the whole reason for choosing
the unreliable mode.

## What this means for the model

`PixelStream/Reassembly.lean` is exactly the right model for this mode. Its
three properties -- monotone emit, no partial presentation, bounded buffer --
are the correct behaviour when a fragment is gone for good and no retransmission
is coming. Under a reliable transport most of that model would be unnecessary;
under datagrams it is the contract.
