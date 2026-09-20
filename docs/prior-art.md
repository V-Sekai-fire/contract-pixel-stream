# Prior art: how deployed engine pixel streaming works

The dominant commercial approach to streaming an engine's output is
WebRTC-based, and it is worth stating plainly because this repository is not
doing that. Trademarks are left out per the working agreements; the architecture
is the genre, not the brand.

## The shape of it

The engine-side plugin captures the back buffer, encodes it on the GPU with the
vendor's hardware encoder, and feeds frames into WebRTC media tracks. Input --
mouse, keyboard, touch, gamepad -- returns over WebRTC data channels. Around
that sits a signalling web server doing WebSocket SDP and ICE exchange and
serving a browser frontend, a selective forwarding unit for multiple viewers, and
a matchmaker routing users to instances. The infrastructure half is Node.js and
TypeScript, MIT licensed, in a repository separate from the engine.

## What WebRTC gives them that this protocol does not

This is the honest part, and it is a longer list than it is comfortable to write:

- **NACK and RTX.** A lost packet is retransmitted, so one missing fragment does
  not destroy a frame. Every loss figure in `codec-measurements.md` assumes it
  does.
- **FEC**, for when retransmission is too slow to help.
- **A bitrate control loop.** The estimate itself is not missing -- see the
  correction below -- but nothing here closes the loop from it to the encoder.
- **PLI and FIR**, so a decoder that has lost sync can ask for a fresh
  intra frame rather than wait.
- **A jitter buffer**, absorbing arrival variance before presentation.
- **RTP fragmentation with sequence numbers** -- which is precisely the problem
  `PixelStream/Reassembly.lean` models and proves. That model is correct, and it
  is also a rediscovery of a solved problem.

## Why this repository is still not adopting it

Two reasons, and only the second is strong.

The weak reason is the JS runtime. The reference infrastructure is Node and
TypeScript, and the working agreements blocklist browser inference and JS
runtime stacks. That argument does not really apply: a signalling server is not
an inference runtime, and nothing forces the frontend to be used.

**The strong reason is what the engine fork actually contains.** Checked:

| module | native implementation | vendored |
| --- | --- | --- |
| `modules/http3` | yes -- QUIC, WebTransport, 9 test pairs | `picoquic`, `picotls`, `webtransportd` |
| `modules/webrtc` | **no** -- `_extension` and `_js` only | nothing |

`modules/webrtc` is an interface plus a browser backend. On a native desktop
target the implementation has to arrive as an external GDExtension. So adopting
WebRTC here means taking on a large third-party media stack, while the QUIC path
is already vendored, already native, and already tested in-tree.

## Correction: QUIC gives back two of these

The list above overstated the gap, and RFC 9221 settles it. DATAGRAM frames
*"employ the QUIC connection's congestion controller"*, and although they are
*"not retransmitted upon loss detection, they are ack-eliciting"* -- so the
sender is told, per datagram, whether it arrived.

That is congestion control and a loss signal for free, which is the raw material
a bitrate controller needs. What remains genuinely absent is retransmission
(given up deliberately), FEC, a jitter buffer, and the control loop that turns
the loss signal into an encoder bitrate.

## What that costs, stated rather than discovered later

Choosing WebTransport over WebRTC is choosing to own the list above. A frame
protocol that fragments and reassembles but never retransmits, never estimates
bandwidth and never tells the encoder to slow down is not a streaming stack; it
is the first quarter of one. `Reassembly.lean` is sound and insufficient.

The order that follows from this: retransmission or FEC for lost fragments, then
a bitrate signal back to the encoder, then jitter handling. Until at least the
first of those exists, the loss columns in `codec-measurements.md` describe the
real behaviour of this design, and they are the argument for building it.
