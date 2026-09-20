-- SPDX-License-Identifier: Apache-2.0 OR MIT

namespace PixelStream

/-- One encoded frame cut into `fragCount` pieces. `echoedInputSeq` is the
highest client input the server had consumed when it rendered. -/
structure Fragment where
  frameSeq : Nat
  fragIndex : Nat
  fragCount : Nat
  echoedInputSeq : Nat
  payload : List UInt8
  deriving Repr, DecidableEq, Inhabited

/-- A fragment is well formed when its index falls inside its own count and the
count is not zero. A zero-count fragment names no frame. -/
def Fragment.wellFormed (f : Fragment) : Prop :=
  0 < f.fragCount ∧ f.fragIndex < f.fragCount

instance (f : Fragment) : Decidable f.wellFormed := by
  unfold Fragment.wellFormed; infer_instance

/-- A reassembled frame, ready to present. -/
structure Frame where
  frameSeq : Nat
  echoedInputSeq : Nat
  payload : List UInt8
  deriving Repr, DecidableEq, Inhabited

end PixelStream
