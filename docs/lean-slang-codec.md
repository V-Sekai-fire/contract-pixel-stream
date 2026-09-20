# A Lean-generated Slang codec: what is feasible

The question: can Lean 4 generate a Slang AV1 encoder and decoder at par with
CineForm? The motivation is sound -- the RTX 3090 has no AV1 block, so a
compute-shader codec would give royalty-free GPU encode on every card rather
than on Ada and newer only.

The answer is no for AV1, yes for a codec of a different shape.

## The pipeline exists and is proven

`3-interactor/cloth-dynamics` generates Slang from Lean today: 49 Lean files,
about 7,900 lines under `lean/Cloth/SlangCodegen/`, gated by `lean-slang.yml`
through `lake build` (with `native_decide` pinning the emitted text), then
`slangc -target spirv` on every kernel, then `slangc -target cpp` plus clang and
a run. `slangc` is on this desk at `scoop/apps/vulkan/current/Bin/slangc`.

So the mechanism is not in question. What it has been pointed at is.

## Why AV1 is the wrong target for it

**The precedent generates numeric kernels; AV1 is mostly not that.** The
existing kernels are `Saxpby`, `DotReduce`, `CGAlpha`, `AssembleB` -- dense
linear algebra for a conjugate-gradient solve, each tens of lines, each
data-parallel, each with an arithmetic property worth proving. An AV1 encoder
needs partition search, tens of intra modes, several transform families at
several sizes, quantization, deblocking, CDEF, loop restoration, and OBU, tile
and header syntax. Most of that is search and bitstream structure rather than
numeric kernels, and it is orders of magnitude more of it.

**The entropy coder is serial by construction and is not optional.** AV1's
symbol-adaptive arithmetic coder adapts its probability model backward, symbol
by symbol, so each symbol depends on every symbol before it. It is the stage a
GPU is worst at, and a conformant bitstream cannot skip it. AV1's tile columns
and rows are entropy-independent, which is the standard escape and gives tile-
count parallelism -- at a compression cost, and bounded by the format's tile
limits.

**"At par with CineForm" is a high bar in the wrong units.** CineForm reaches
roughly 8.9 ms a frame at 1080p as mature hand-tuned SIMD. A first-generation
generated encoder is not going to land near that, and the comparison flatters
AV1's compression while ignoring that the two codecs are not solving the same
problem.

## What is feasible, and hits the actual requirement

The requirement is royalty-free GPU encode that works on a card without an AV1
block. AV1 is one way to be royalty-free; it is not the only one, and it is the
hardest to implement.

**An intra-only wavelet codec is the tractable target.** It is the shape
CineForm already is, and it suits both halves of this: the discrete wavelet
transform is separable and data-parallel, which is what compute shaders and the
existing codegen are good at, and its correctness properties -- transform
invertibility, reconstruction error bounds, quantization round-trip -- are
exactly what Lean proves well. There is no motion search, no partition search,
no mode decision, and the coefficient coding is far simpler than AV1's.

A staged shape, where each stage is worth having alone:

1. Forward and inverse DWT as Lean-generated Slang kernels, with invertibility
   proved and checked against the emitted SPIR-V by the existing three-layer
   gate.
2. Quantization and dequantization, with the round-trip error bound proved.
3. Coefficient coding on the CPU first. Parallelize it only if measurement says
   it is the bottleneck.
4. Measure against CineForm on the same frames: ms per frame, Mbps, PSNR.

Stage 1 alone answers the real question -- whether Lean-generated Slang reaches
useful throughput on this workload -- before anything commits to a bitstream.

## What would change the answer

If the goal is specifically an **AV1 bitstream** rather than royalty-free GPU
encode, the tractable subset is intra-only, one transform size, fixed
partitioning, tile-parallel entropy coding, with the parallel stages generated
from Lean and the entropy coder written by hand per tile. That is a real
project and it will not be at par with CineForm on speed. It would be worth it
only if AV1 decode on the receiving end is itself the requirement, because then
every client already has a hardware decoder.

That is the question to settle first: is the requirement a bitstream that
hardware decoders accept, or royalty-free encode on any GPU? They point at
different codecs.

## Not measured

Nothing here is measured. No DWT kernel was written or timed, and the claim
that a wavelet transform reaches useful throughput in Slang on this hardware is
an expectation, not a result. Stage 1 above exists to replace this paragraph
with a number.
