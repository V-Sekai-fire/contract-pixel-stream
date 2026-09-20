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
| NVENC HEVC, RTX 4090 | 942.7 | 1.06 | 19.4 | driver; HEVC patent pools |
| NVENC H.264, RTX 4090 | 631.5 | 1.58 | 30.9 | driver; H.264 patent pools |

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
License 1.0 is an actual royalty-free grant. HEVC and H.264 have active pools.

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

## What is still open

- The CineForm baseline needs measuring here before this table is quoted.
- AV1 at 26.9 Mbps is ~2800 datagrams a frame at 1200 bytes, so the
  datagram-versus-stream-per-frame question in the README is unchanged by these
  numbers and still wants its own measurement.
- Nothing here measures *latency*, only throughput. 1.75 ms a frame is encode
  cost, not glass-to-glass.
- The RTX 3090 has no AV1 encoder. A two-card desk is not a uniform target, and
  the fallback path is unmeasured.
