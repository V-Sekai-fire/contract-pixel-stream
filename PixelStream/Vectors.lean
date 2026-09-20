-- SPDX-License-Identifier: Apache-2.0 OR MIT

import PixelStream.Reassembly

namespace PixelStream

/-- Feed a whole delivery trace through the model. -/
def run (cap : Nat) (fs : List Fragment) : List Frame :=
  (fs.foldl
    (fun (acc : State × List Frame) f =>
      let r := step acc.1 f
      (r.1, acc.2 ++ r.2.toList))
    (State.init cap, [])).2

structure Trace where
  name : String
  capacity : Nat
  fragments : List Fragment
  expect : List Frame
  deriving Repr

private def frag (seq i n e : Nat) (p : List UInt8) : Fragment :=
  { frameSeq := seq, fragIndex := i, fragCount := n, echoedInputSeq := e, payload := p }

private def frm (seq e : Nat) (p : List UInt8) : Frame :=
  { frameSeq := seq, echoedInputSeq := e, payload := p }

/-- The corpus is enumerated rather than sampled: the defect classes are a
fixed population, and a sampled run would only see defects larger than ~3/n. -/
def corpus : List Trace :=
  [ { name := "in-order", capacity := 4
    , fragments := [frag 1 0 3 7 [1], frag 1 1 3 7 [2], frag 1 2 3 7 [3]]
    , expect := [frm 1 7 [1, 2, 3]] }
  , { name := "reordered", capacity := 4
    , fragments := [frag 1 2 3 7 [3], frag 1 0 3 7 [1], frag 1 1 3 7 [2]]
    , expect := [frm 1 7 [1, 2, 3]] }
  , { name := "dropped-fragment", capacity := 4
    , fragments := [frag 1 0 3 7 [1], frag 1 2 3 7 [3]]
    , expect := [] }
  , { name := "duplicate-fragment", capacity := 4
    , fragments := [frag 1 0 2 7 [1], frag 1 0 2 7 [1], frag 1 1 2 7 [2]]
    , expect := [frm 1 7 [1, 2]] }
  , { name := "two-frames", capacity := 4
    , fragments := [frag 1 0 1 7 [1], frag 2 0 1 9 [2]]
    , expect := [frm 1 7 [1], frm 2 9 [2]] }
  , { name := "stale-after-newer", capacity := 4
    , fragments := [frag 2 0 1 9 [2], frag 1 0 1 7 [1]]
    , expect := [frm 2 9 [2]] }
  , { name := "index-past-count", capacity := 4
    , fragments := [frag 1 3 2 7 [1]]
    , expect := [] }
  , { name := "zero-count", capacity := 4
    , fragments := [frag 1 0 0 7 [1]]
    , expect := [] }
  ]

/-- The model agrees with every declared expectation, checked at build time. -/
example : corpus.all (fun t => run t.capacity t.fragments == t.expect) = true := by native_decide

end PixelStream
