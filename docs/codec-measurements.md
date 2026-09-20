# Codec candidates, measured

The question this answers: is there a permissively licensed codec as fast as
CineForm, and does anything solve CineForm's bitrate?

Measured 2026-09-20 on one desk: 16-thread CPU, RTX 3090 + RTX 4090, Windows 11
26200. Source is 120 frames of 1920x1080 high-detail synthetic noise with a
panning offset -- deliberately harder than rendered game content, so the
bitrates are upper bounds and the CPU frame rates are lower bounds.

| encoder | fps | ms/frame | Mbps | licence |
| --- | --- | --- | --- | --- |
| CineForm (**borrowed figure; see the two sections on it below**) | 112 | 8.9 | 470 | Apache-2.0 OR MIT |
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
times less wire -- **but the bitrate half of that is withdrawn below as not
quality-matched**, so treat the direction as sound and the multiplier as
unestablished. 470 Mbps saturates half a gigabit link for one viewer; 26.9
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

**This retracts the recommendation two sections above** (itself later
un-retracted -- see "nvenc.sigs is restored"). That text proposes an
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

## nvenc.sigs is restored

The Vulkan Video section retracted the `nvenc.sigs` recommendation. The section
after it withdrew Vulkan Video. Withdrawing the replacement should have restored
what it replaced, and did not -- so the chain is recorded here rather than
tidied away, and `nvenc.sigs` stands.

It is the right mechanism twice over. The `contract-bus` pattern exists for
exactly a library the engine must not link: `iceoryx2.sigs` lists the C ABI,
`generate_stubs.py` emits a dlsym dispatch table, and in its own words there is
*"no -liceoryx2_ffi_c at link time, and no iceoryx2 headers at build time... it
fails at start rather than at link if the library is absent."* That is the
property wanted for an encoder -- no vendor SDK in the tree, no relinking
obligation, and a clear runtime failure on a desk with no encoder.

And it matches how NVENC is built to be used. The entry point is
`NvEncodeAPICreateInstance` in the driver's own library -- `nvEncodeAPI64.dll`
on Windows, `libnvidia-encode.so` on Linux -- which fills in a struct of
function pointers. NVENC is already a runtime-loaded function table by design;
`nvenc.sigs` writes that table down where the build can check it instead of
leaving it hand-maintained.

It also composes with what the measurements settled. The 3090 refuses AV1 at
`CreateEncoder` rather than falling back silently, so the capability check has a
place to live: the dispatch table loads, the encoder is asked for AV1, and the
refusal is a start-time failure naming the card -- not a silent downgrade to an
encumbered codec, which is the failure this document has spent two retractions
avoiding.

## CineForm does have a smaller form, and the earlier comparison was not fair

Measured on this desk at last, so the borrowed baseline above is partly
replaced. Same source, 1920x1080 4:4:4 BGRA from the high-detail clip's luma,
24 frames, **one encoder, not the pool**:

| quality | Mbps | KiB/frame | vs default |
| --- | --- | --- | --- |
| LOW | 2062.4 | 4196 | 0.62x |
| MEDIUM | 2635.1 | 5361 | 0.80x |
| HIGH *(module default)* | 3309.0 | 6732 | 1.00x |
| FILMSCAN1 | 3738.4 | 7606 | 1.13x |
| FILMSCAN2, FILMSCAN3 | encoder exits | -- | -- |

So yes: `modules/cineform` defaults to index 2, `HIGH`, and `LOW` and `MEDIUM`
sit below it. `LOW` is a little under two thirds the size of the default. That
is the smaller form, and it is a quality knob rather than a different codec.

**Three things this run does not support, and one it withdraws.**

The frame rates are not comparable to anything above. The async encoder pool
never returned a sample on this desk -- submissions were accepted, and
`CFHD_WaitForSample` then blocked forever -- so this uses the synchronous
`CFHD_EncodeSample` path with a single encoder. About 28 fps single-threaded
against a published 112 fps on sixteen threads is consistent, but it is not a
measurement of the same thing and must not be put in the same column.

`FILMSCAN2` and `FILMSCAN3` end the process. Reproducible across runs, no
output on stderr, and the four levels before them are byte-identical each time.
Not investigated.

The source flatters nobody. High-detail synthetic noise is close to worst case
for a wavelet codec, which is why these figures sit far above RFD 1137's 0.47
Gbit/s. That is the clip, not the codec.

**And the withdrawal.** The first table in this document put CineForm's 470
Mbps beside AV1's 26.9 Mbps and called it seventeen times less wire. That
comparison is not quality-matched: CineForm was encoding near-losslessly while
SVT-AV1 and NVENC ran at CRF 35, quantizing hard. Two codecs at different
quality targets cannot be divided. The direction almost certainly holds --
hardware AV1 is dramatically smaller for streaming -- but **the multiplier is
not established by anything measured here**, and the earlier figure should not
be quoted until a quality-matched run exists.

## Tuning CineForm down: 4:2:2 is the lever, and it still does not reach AV1

Three knobs exist. Measured together, 1080p, 24 frames, single encoder:

| clip | format | LOW | MEDIUM | HIGH | FILMSCAN1 |
| --- | --- | --- | --- | --- | --- |
| high-detail noise | 4:4:4 | 2062 | 2635 | 3309 | 3738 |
| high-detail noise | 4:2:2 | **773** | 857 | 1071 | 1352 |
| smooth gradient | 4:4:4 | 161 | 169 | 184 | 208 |
| smooth gradient | 4:2:2 | **90.5** | 93.6 | 98.9 | 107 |

All figures Mbps at 60 fps.

**`CFHD_ENCODED_FORMAT_YUV_422` is the biggest single lever and it was being
left on the table.** `modules/cineform` encodes `RGB_444` (or `RGBA_4444` when
alpha is kept). Switching to 4:2:2 cuts the wire by 2.7x on hard content and
1.8x on easy, *and* roughly doubles encode speed -- 53 fps against 27 on the
same clip and encoder. For a stream it is better on both axes at once. The cost
is chroma resolution, which shows on text and thin UI edges and rarely on
rendered 3D.

Quality level is the weakest knob: LOW to FILMSCAN1 spans only 1.8x on hard
content and 1.3x on easy. Content dominates everything -- 13x between the two
clips at the same settings.

**But the answer to "closer to AV1" is no.** Best measured CineForm is 90.5
Mbps, on easy content at 4:2:2 LOW. NVENC AV1 on that same easy clip was 0.38
Mbps, and 26.9 Mbps on the hard one at 4:2:2's 773. The gap is between 29x and
240x depending on the clip, and neither pair is quality-matched, so treat those
as magnitudes rather than ratios.

That is not a tuning failure, it is the codec's design. CineForm is a mezzanine
codec built to sit around 10:1 from uncompressed and stay visually lossless
through repeated edits. 1080p60 4:2:2 8-bit uncompressed is roughly 2 Gbps, so
90 Mbps is already past its nominal ratio. Asking it for delivery bitrates asks
it to stop being the thing it was chosen for.

**What this changes.** 4:2:2 should be adopted regardless -- it is free speed
and a third of the wire for a LAN deployment, and it makes the 10GbE row in the
ranking comfortable rather than marginal. It does not move CineForm out of the
LAN row and into the WAN row. Hardware AV1 stays the WAN answer.

## HDR: the engine throws it away, and the obvious fix is not yet safe

`MovieWriter::_request_frame_async` supports `R16G16B16A16_SFLOAT` and hands
back `FORMAT_RGBAH`. `MovieWriterCineForm::write_frame` then does this,
unconditionally, before the encoder is called:

    if (img->get_format() != Image::FORMAT_RGBA8) {
        img->convert(Image::FORMAT_RGBA8);
    }

So high dynamic range and high bit depth are already gone today, at the writer,
not at the codec. RFD 1123 reasons about 12-bit CineForm and about `FORMAT_RGBAH`
losing the bottom bit -- reasoning that only makes sense if depth reaches the
encoder. It does not. That is a larger defect than the chroma format beside it.

**The shape of the fix is clear.** CineForm takes 16-bit input directly:
`CFHD_PIXEL_FORMAT_RG64` is 16-bit RGBA on the encoder side, and the codec's own
`WP13` decoder format documents a whitepoint at `1<<13`. Scaling half-float so
1.0 lands on 8192 rather than 65535 keeps 13 bits below white and leaves three
stops of highlight headroom, instead of clipping at white the way an 8-bit
conversion does.

**It encodes. It has not been shown to decode.** Fed RG64 at that scaling, the
encoder accepts every frame and produces output three times *smaller* than the
8-bit path -- 673.8 Mbps against 2062.4 at LOW. A smaller file with no quality
check is not a better one; it is equally consistent with the signal having been
quantized into the floor. The round-trip decode back to RG64 ends the process
before a single row prints, so there is no PSNR for the 16-bit path and no
evidence it survives.

**So the engine is not changed.** Wiring an unverified colour conversion into
the writer would replace a known, honest loss with an unknown one. What it needs
first is a working `CFHD_PrepareToDecode`/`CFHD_DecodeSample` round trip at
RG64, and a PSNR against the source.

## What the round trip did establish: the quality ladder is a real quality cut

Decoding the 8-bit path back and scoring the first frame against its source, on
the high-detail clip:

| quality | Mbps | PSNR |
| --- | --- | --- |
| LOW | 2062.4 | **28.6 dB** |
| MEDIUM | 2635.1 | 34.6 dB |
| HIGH | 3309.0 | 40.3 dB |
| FILMSCAN1 | 3738.4 | 42.6 dB |

This corrects the earlier ladder table, which gave sizes and no quality and so
made `LOW` look like a free 0.62x. It is not free: on this content `LOW` is 28.6
dB, nowhere near visually lossless, and the 12 dB between `LOW` and `FILMSCAN1`
is most of what the extra bitrate buys. Any future comparison against AV1 has to
put both codecs at a matched PSNR, which is exactly the quality-matching this
document withdrew a ratio for lacking.

## Decision: CineForm is not the pixel-streaming codec

Tuned as far as it goes -- 4:2:2, LOW quality -- CineForm reaches 773 Mbps on
high-detail content at 28.6 dB. Better than the 3309 Mbps it started at, and
still not a streaming codec. The arithmetic that settles it is fragmentation,
not bandwidth.

At a 1200-byte datagram with an 18-byte header, one frame becomes this many
fragments, and a frame dies if any one of them is lost:

| codec | bytes/frame | fragments | frame loss @0.1% | @1% |
| --- | --- | --- | --- | --- |
| CineForm 4:4:4 HIGH | 6,893,750 | 5833 | 99.7% | 100% |
| CineForm 4:2:2 LOW | 1,611,042 | 1363 | **74.4%** | 100% |
| CineForm, RFD 1137's figure | 979,167 | 829 | 56.4% | 100% |
| NVENC AV1, high-detail clip | 56,042 | **48** | **4.7%** | 38.3% |
| NVENC AV1, smooth clip | 792 | 1 | 0.1% | 1.0% |

Three quarters of frames dying on a tenth of a percent of packet loss is not a
tuning problem. **Hardware AV1 is the pixel-streaming codec**, and CineForm
stays what it is good at: the mastering path behind `--write-movie`, where
visually lossless matters and 470 Mbps to a local disk is free.

## This also answers the datagram question

The README raises datagrams versus one reliable QUIC stream per frame as an open
question, on the grounds that roughly 1250 datagrams a frame makes a single loss
fatal. That arithmetic was CineForm's. At AV1's 48 fragments it changes sign:

- **Datagrams are viable** at low loss -- 4.7% of frames dropped at 0.1%, which
  for video is a dropped frame rather than a broken stream, especially with
  `encode_intra_refresh` recovering without a keyframe request.
- **They stop being viable around 1%**, where 38% frame loss arrives. That is
  where a reliable stream per frame, or FEC, earns its cost.

So the design is a loss-dependent choice rather than a fixed one, and the
protocol should carry both paths rather than pick now. `WebTransportPeer`
already exposes both, and `Reassembly.lean` already proves the datagram side is
safe under reorder and loss.

## What is still open

- The CineForm baseline is now partly measured here, single-threaded only. The
  pool path still needs to work before a like-for-like frame rate exists, and no
  run yet matches quality across codecs, which is what a bitrate ratio needs.
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
