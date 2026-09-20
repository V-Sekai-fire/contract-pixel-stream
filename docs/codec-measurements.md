# Codec candidates, measured

The question this answers: is there a permissively licensed codec as fast as
CineForm, and does anything solve CineForm's bitrate?

Measured 2026-09-20 on one desk: 16-thread CPU, RTX 3090 + RTX 4090, Windows 11
26200. Source is 120 frames of 1920x1080 high-detail synthetic noise with a
panning offset -- deliberately harder than rendered game content, so the
bitrates are upper bounds and the CPU frame rates are lower bounds.

| encoder | fps | ms/frame | Mbps | licence |
| --- | --- | --- | --- | --- |
| CineForm (**not measured here** -- see below) | 112 | 8.9 | 470 | Apache-2.0 OR MIT |
| SVT-AV1 preset 13, CPU, 16 threads | 60.3 | 16.6 | 21.8 | BSD-3-Clause-Clear + AOM Patent 1.0 |
| SVT-AV1 preset 12, CPU, 16 threads | 60.9 | 16.4 | 21.8 | same |
| SVT-AV1 preset 10, CPU, 16 threads | 55.6 | 18.0 | 20.9 | same |
| NVENC AV1, RTX 4090 | **571.6** | **1.75** | **26.9** | driver, loaded at runtime |
| NVENC HEVC, RTX 4090 | 942.7 | 1.06 | 19.4 | driver; **HEVC pools -- rejected, see below** |
| NVENC H.264, RTX 4090 | 631.5 | 1.58 | 30.9 | driver; **AVC pool -- rejected, see below** |

SVT-AV1 v4.2.0, low delay (`--pred-struct 1 --lookahead 0`), CRF 35.
NVENC via PyNvVideoCodec 2.2.3, preset P1, `ultra_low_latency`, timings include
the CPU-side NV12 upload.

## The baseline is borrowed, and that weakens the table

**The CineForm row was not measured on this desk.** It is RFD 1137's figure
(0.47 Gbit/s at 1080p60) and `interactor-cineform`'s README (112 fps at 1080p on
16 threads). The CineForm SDK builds here -- `CFHDCodecStatic.lib` was produced
from `7-service/cineform/thirdparty/cineform-sdk` -- but no encode harness was
written against `CFHD_EncoderPool`, so the comparison is not like-for-like and
should not be quoted as one until it is.

## What the numbers say

**Hardware AV1 wins on both axes at once.** 1.75 ms a frame against CineForm's
~8.9, and 26.9 Mbps against 470. That is five times the speed and seventeen
times less wire. 470 Mbps saturates half a gigabit link for one viewer; 26.9
Mbps is about one 4K streaming-service video, and fits an ordinary home uplink.

**Software AV1 does not.** At preset 12-13 it reaches 60 fps for 1080p60 -- with
all sixteen threads. The renderer needs those threads, so CPU AV1 is not a
real-time option on the same box as the render. It is a fallback for a desk with
no encoder, and should be labelled that way.

**HEVC is faster than AV1 and smaller, and is still the wrong answer.** The
speed is real; the patent position is not comparable. AV1's AOMedia Patent
License 1.0 is an actual royalty-free grant. HEVC and H.264 have active pools,
and HEVC's are the worst of any option here -- see the rejection below, which
also withdraws a later section of this document that recommended HEVC anyway.

## Why AV1 rather than JPEG XS

JPEG XS is the closer analogue to CineForm -- a mezzanine codec with sub-frame
latency -- and SVT-JPEG-XS carries the OSI BSD+Patent licence, which looks like
the right shape. Two things rule it out here.

Intel's own notice says you are solely responsible for determining whether your
use of JPEG XS requires additional licences, and that Intel is not responsible
for obtaining them. BSD+Patent covers Intel's contribution to that code; it does
not grant the standard's essential patents. That is the FFmpeg-shaped problem
wearing a permissive licence.

SVT-JPEG-XS is also x86-64 only. CineForm reaches arm64 through sse2neon, and
`modules/cineform/config.py` already builds for it.

## The dependency problem is solved by not linking

The reason FFmpeg is blocklisted is LGPL relinking against a single static Godot
export. A vendor encoder avoids the licence but reintroduces the dependency --
unless it is never linked.

`2-contract/bus` already does this for iceoryx2, and did it for GStreamer before
that: `iceoryx2.sigs` lists the C ABI, `generate_stubs.py` emits a dlsym dispatch
table, and in its own words there is *"no -liceoryx2_ffi_c at link time, and no
iceoryx2 headers at build time... it fails at start rather than at link if the
library is absent."*

An `nvenc.sigs` gives the same property for the encoder: nothing linked, no
vendor SDK in the tree, no relinking obligation, and a clear runtime failure on
a machine with no encoder rather than a build that cannot be produced.

## Reranked, once texture sharing is on the list

Spout is not a codec, and that is exactly why it outranks every codec for one
of the cases this project targets. It shares the GPU texture itself between
processes on one machine through a DirectX 11 shared texture -- no encode, no
bitstream, no bitrate, and nothing to be patented. Published figure is about
0.45 ms for 4K60. Licence is BSD 2-Clause. Syphon is the macOS equivalent, MIT.

So the ranking is not one list, it is one list per deployment:

| case | first choice | cost |
| --- | --- | --- |
| client and server on one machine | **Spout** (Windows) / **Syphon** (macOS) | Windows-only and macOS-only respectively; no network at all |
| one LAN | NVENC AV1 -- 1.75 ms, 26.9 Mbps | needs an encoder on the box; RTX 3090 has none |
| over a WAN | NVENC AV1 | the only row that fits a home uplink |
| no encoder present | SVT-AV1 preset 12 | 60 fps only by taking all 16 threads |
| 10GbE and latency above all | CineForm, 470 Mbps | will not leave a LAN |

**The uncomfortable part.** For the same-machine case, Spout does not merely
beat the codecs -- it removes the need for this repository's frame protocol
entirely. There is no fragmentation, no reassembly and no loss to reason about
when the consumer reads the producer's texture. Several of the targets named in
the README are same-machine: CI screenshotting, and feeding a local capture or
streaming application.

That does not sink the protocol, but it does narrow its claim. The frame
protocol earns its place when a network is between the two ends, and the honest
statement of scope is that a same-machine consumer should use texture sharing
and skip all of this. An RFD that says so is stronger than one that quietly
covers the same-machine case with a worse mechanism.

**What Spout does not do.** It does not cross machines, so it replaces nothing
for thin clients or render farms. It is also per-platform in a way the codecs
are not: three mechanisms (Spout, Syphon, and DMABUF or PipeWire on Linux)
against one AV1 bitstream, on a launcher that already ships four targets. None
of the three is measured on this desk yet -- the figures above are published,
not observed here, and `modules/texture_streaming` in the fork is GPU asset
streaming, unrelated to frame export.

## A GPGPU AV1 encoder, and why the answer is Vulkan Video instead

The thing asked for -- AV1 encoded entirely in compute shaders, vendor-neutral,
no fixed-function block -- is real but not shippable here.

It exists: FFmpeg's Vulkan work runs motion estimation, transform, quantization
and entropy coding as compute, actively developed in mainline as of 2026. It is
also the one codebase this workspace cannot link, for the reason FFmpeg is
blocklisted in the first place.

And there is a structural reason it stays hard. AV1's entropy coder is a
symbol-adaptive arithmetic coder whose backward adaptation is strictly serial in
the coefficients, and intra prediction depends on neighbouring blocks, so the
two least parallel stages are the two a GPU is worst at. Forward-adaptation
modes parallelize; the default does not.

**The property actually wanted is vendor neutrality, not GPGPU** -- an encoder
that is not NVIDIA-only. Vulkan Video delivers that without compute shaders, by
putting the fixed-function block behind a Khronos extension that AMD and Intel
implement too.

Measured on this desk, per device rather than from a merged extension list:

| GPU | `VK_KHR_video_encode_av1` | `..._intra_refresh` | `..._quantization_map` |
| --- | --- | --- | --- |
| RTX 4090 | **yes** | yes | yes |
| RTX 3090 | **no** | yes | yes |

Driver 616.92. The per-device split is the point: Ampere has no AV1 encoder, and
a merged list would have reported AV1 support for a card that has none.

Two of those extensions bear directly on problems already written down here.
`encode_intra_refresh` replaces periodic keyframes with a rolling intra region,
which removes the keyframe bitrate spike and lets a decoder recover from loss
without a keyframe request -- the storm `PixelStream/Reassembly` was going to
need a rule against. `encode_quantization_map` gives per-region quantization,
so a foveated or region-of-interest stream costs nothing extra in protocol.

**This retracts the recommendation two sections above.** That text proposes an
`nvenc.sigs` dlopen table on the `contract-bus` pattern. Vulkan Video is the
better answer and needs no such thing: Godot is already a Vulkan engine holding
a `VkDevice`, so the encoder is reached through the API the renderer already
uses -- no vendor SDK, no dlopen, no new dependency mechanism, and AMD and Intel
work for free. The `.sigs` pattern remains correct for a library the engine does
not already link; it is simply not needed for this one.

The fork does not touch Vulkan Video today: nothing in `drivers/vulkan/` or
`servers/rendering/` references `VK_KHR_video` or `vkCmdEncodeVideo`. Exposing a
video-encode queue is engine work that does not exist yet, and it is larger than
calling NVENC would be. That is the trade -- more work now, one path for three
vendors afterwards.

## Retracted: Vulkan Video is not warranted, NVENC directly is

The section above recommends Vulkan Video over NVENC for vendor neutrality.
That recommendation is withdrawn, for a reason the measurement already contained.

The operator's compute is two NVIDIA cards, and the working agreements say owned
GPUs are the only compute. Vendor neutrality therefore buys nothing today: there
is no AMD or Intel card for the abstraction to reach. Against that, the same
section concedes the cost in its own words -- exposing a Vulkan video-encode
queue is engine work larger than calling NVENC would be, and the fork references
no `VK_KHR_video` symbol today.

Nor does Vulkan Video paper over the split inside this desk. `VK_KHR_video_encode_av1`
is absent on the 3090, so the abstraction does not make one path across the
operator's own two cards; it makes the same two paths behind a longer route.

So: **NVENC directly on the 4090, HEVC on the 3090.** `intra_refresh` is an NVENC
feature rather than a Vulkan one, so the capability that matters for loss
recovery is not given up. Vulkan Video becomes worth revisiting when a non-NVIDIA
card is actually owned, and not before.

## The device index is not the device, and the encoder says so out loud

Resolving which card produced the AV1 numbers turned up a trap worth recording.

`nvidia-smi` reports index 0 as the RTX 3090 and index 1 as the RTX 4090. CUDA
does not use that order: its default is fastest-first, so CUDA device 0 is the
4090. Pinning the order makes it unambiguous:

| ordering | device 0 | device 1 |
| --- | --- | --- |
| `nvidia-smi` (PCI) | 3090 | 4090 |
| CUDA default (fastest first) | 4090 | 3090 |
| `CUDA_DEVICE_ORDER=PCI_BUS_ID`, AV1 accepted? | no | yes |

The AV1 figures in the first table were produced under CUDA's default ordering
and are therefore the 4090's. They stand.

**And the important half: there is no silent fallback.** Asked for AV1 on the
3090, NVENC refuses with `PyNvEncoderCaps` rather than quietly encoding
something else or dropping to the CPU. That is the failure mode the Mitsuba row
in `BLOCKLIST.md` exists to warn about, and this encoder does not have it. A run
that reports AV1 on this desk really did use the AV1 block.

Per card, 60-frame runs, same source:

| card | AV1 | HEVC |
| --- | --- | --- |
| RTX 4090 | 2.39 ms, 30.3 Mbps | 1.10 ms, 20.2 Mbps |
| RTX 3090 | **refused** | 2.64 ms, 20.1 Mbps |

The 120-frame figures in the first table are the better estimate; these shorter
runs carry more start-up cost per frame.

## HEVC is out, and that makes the 3090 not a streaming server

The section above recommends HEVC on the 3090. That is withdrawn too, and it
contradicted this document's own table, which already recorded that HEVC and
H.264 carry active patent pools before recommending one of them anyway.

HEVC is the worst of the options on licensing, not merely encumbered: several
competing pools plus holders in none of them, and royalties that have been
asserted against distributing content rather than only against encoders. AV1
exists to escape exactly that, and AOMedia Patent License 1.0 is the escape.
H.264 is calmer but is the same category, so swapping HEVC for H.264 is not a
fix, it is a smaller dose.

What that leaves is a hardware fact rather than a codec choice:

| card | royalty-free hardware encode | so |
| --- | --- | --- |
| RTX 4090 | AV1 | the streaming server |
| RTX 3090 | **none** | not a streaming server |

The 3090 has no royalty-free hardware encoder at all. Its only clean paths are
software, and both are poor for streaming: SVT-AV1 at 60 fps only by taking all
sixteen threads the renderer needs, or CineForm at 470 Mbps which will not leave
a LAN. Neither is a fallback so much as a different deployment.

So the honest statement is a requirement: **hardware AV1 encode, which today
means Ada or newer.** A desk without it renders locally, shares by texture, or
streams on a LAN in CineForm -- it does not become a WAN streaming server by
picking a more encumbered codec. Writing that down as a requirement is better
than shipping HEVC and discovering the licence later.

This also shifts the earlier ranking. For the same-machine case Spout was
already first on latency; it is now first on licensing as well, because sharing
a texture encodes nothing and so infringes nothing. And CineForm's 470 Mbps buys
something the table did not credit it for: Apache-2.0 OR MIT with no pool behind
it, which on a 10GbE segment is a perfectly defensible trade.

## What is still open

- The CineForm baseline needs measuring here before this table is quoted.
- AV1 at 26.9 Mbps is ~2800 datagrams a frame at 1200 bytes, so the
  datagram-versus-stream-per-frame question in the README is unchanged by these
  numbers and still wants its own measurement.
- Nothing here measures *latency*, only throughput. 1.75 ms a frame is encode
  cost, not glass-to-glass.
- The RTX 3090 has no AV1 encoder. A two-card desk is not a uniform target, and
  the fallback path is unmeasured.
- No Vulkan Video encode was ever run here; only extension presence was
  checked, and the recommendation that rested on it is now withdrawn. Presence is not throughput, and the NVENC figures above are NVENC's,
  not Vulkan Video's, even though the silicon is the same block.
- Spout, Syphon and the Linux equivalent are unmeasured here. The same-machine
  case deserves its own measurement before the scope narrowing above is written
  into an RFD as settled.
