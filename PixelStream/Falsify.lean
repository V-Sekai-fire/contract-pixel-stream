-- SPDX-License-Identifier: Apache-2.0 OR MIT

import PixelStream.Vectors

/-!
Randomized falsification, decided rather than admitted.

`plausible` was the obvious tool and is not used: its tactic searches for a
counter-example and, finding none, closes the goal with `sorry`. That exports a
tested guess as a proven fact, so the search is done here over a seeded
generator and the result is settled by `native_decide`. Nothing in this file is
admitted, and the seed is written down so a failure is reproducible.
-/

namespace PixelStream

def xorshift (x : UInt32) : UInt32 :=
  let a := x ^^^ (x <<< 13)
  let b := a ^^^ (a >>> 17)
  b ^^^ (b <<< 5)

/-- `n` pseudorandom numbers from `seed`. -/
def stream (seed : UInt32) : Nat → List Nat
  | 0 => []
  | k + 1 => let s := xorshift seed; s.toNat :: stream s k

def traceOf (ns : List Nat) (frames slices : Nat) : List Fragment :=
  ns.map (fun n =>
    { frameSeq := n % frames + 1
    , fragIndex := n / frames % slices
    , fragCount := slices
    , echoedInputSeq := n % 7
    , payload := [UInt8.ofNat (n % 251)] })

def emittedSeqs (fs : List Frame) : List Nat := fs.map (·.frameSeq)

def strictlyIncreasing : List Nat → Bool
  | [] => true
  | [_] => true
  | a :: b :: rest => a < b && strictlyIncreasing (b :: rest)

/-- The three properties, as one decidable predicate over a trace. -/
def holds (fs : List Fragment) : Bool :=
  let out := run 4 fs
  let seqs := emittedSeqs out
  strictlyIncreasing seqs
    && seqs.all (fun s => fs.any (fun f => f.frameSeq == s))
    && (seqs.eraseDups).length == seqs.length

/-- Draw `trials` traces from `seed` and check every one. -/
def sweep (seed : UInt32) (trials len : Nat) : Bool :=
  (List.range trials).all (fun i =>
    holds (traceOf (stream (seed + UInt32.ofNat i) len) 3 3))

/-- Seed 0x2545F491, 400 traces of 24 fragments each. -/
example : sweep 0x2545F491 400 24 = true := by native_decide

/-- The defect a hand-written reassembler ships: emit on the first fragment. -/
def brokenRun (fs : List Fragment) : List Frame :=
  fs.map (fun f =>
    { frameSeq := f.frameSeq, echoedInputSeq := f.echoedInputSeq, payload := f.payload })

def brokenHolds (fs : List Fragment) : Bool :=
  strictlyIncreasing (emittedSeqs (brokenRun fs))

/-- The control. A sweep that passes is worth nothing unless failure is
reachable, so the same generator is run against the broken reassembler and must
find a counter-example. -/
example : (List.range 400).any
    (fun i => !brokenHolds (traceOf (stream (0x2545F491 + UInt32.ofNat i) 24) 3 3)) = true := by
  native_decide

end PixelStream
