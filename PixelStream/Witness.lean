-- SPDX-License-Identifier: Apache-2.0 OR MIT

import PixelStream.Vectors

/-!
The counter-example search, posed as a witness query.

`plausible`'s tactic is not used here: it closes a goal it cannot falsify by
admitting it, which exports a tested guess as a proven fact. `plausible-witness-dag`
drives the same engine through `Testable.checkIO`, so the search runs as a
program and nothing is admitted. It also reports `budgetHit` separately from
`provablyNone`, which is the distinction that matters -- an exhausted budget
must not read as a clean negative.
-/

namespace PixelStream

def xorshift (x : UInt32) : UInt32 :=
  let a := x ^^^ (x <<< 13)
  let b := a ^^^ (a >>> 17)
  b ^^^ (b <<< 5)

def stream (seed : UInt32) : Nat → List Nat
  | 0 => []
  | k + 1 => let s := xorshift seed; s.toNat :: stream s k

/-- Candidate `n` names one delivery trace. -/
def traceOfCandidate (n : Nat) (len : Nat := 24) : List Fragment :=
  (stream (UInt32.ofNat n + 1) len).map (fun m =>
    { frameSeq := m % 3 + 1
    , fragIndex := m / 3 % 3
    , fragCount := 3
    , echoedInputSeq := m % 7
    , payload := [UInt8.ofNat (m % 251)] })

def emittedSeqs (fs : List Frame) : List Nat := fs.map (·.frameSeq)

def strictlyIncreasing : List Nat → Bool
  | [] => true
  | [_] => true
  | a :: b :: rest => a < b && strictlyIncreasing (b :: rest)

/-- The properties, as one predicate over an emitted sequence. -/
def outputOk (fs : List Fragment) (out : List Frame) : Bool :=
  let seqs := emittedSeqs out
  strictlyIncreasing seqs
    && seqs.all (fun s => fs.any (fun f => f.frameSeq == s))
    && (seqs.eraseDups).length == seqs.length

/-- The reassembler under test. -/
def goodOut (fs : List Fragment) : List Frame := run 4 fs

/-- The defect a hand-written reassembler ships: emit on the first fragment. -/
def brokenOut (fs : List Fragment) : List Frame :=
  fs.map (fun f =>
    { frameSeq := f.frameSeq, echoedInputSeq := f.echoedInputSeq, payload := f.payload })

/-- A candidate is a witness when its trace breaks the properties. Finding one
means the reassembler is wrong. -/
def violates (out : List Fragment → List Frame) (n : Nat) : Bool :=
  let t := traceOfCandidate n
  !outputOk t (out t)

/-- First violating candidate within a walk budget, searched deterministically
so a reported witness is reproducible from its index alone. -/
def firstViolation (out : List Fragment → List Frame) (steps : Nat) : Option Nat :=
  (List.range steps).find? (violates out)

end PixelStream
