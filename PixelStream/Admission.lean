-- SPDX-License-Identifier: Apache-2.0 OR MIT

import PixelStream.Wire

namespace PixelStream

/-- The encoder pool and the send queue, as depths and occupancies. `wire`
holds fragments accepted for transmission but not yet sent. -/
structure Admit where
  poolDepth : Nat
  sendDepth : Nat
  queued : Nat
  wire : List Fragment
  deriving Repr, Inhabited

def Admit.wellFormed (a : Admit) : Prop :=
  a.queued ≤ a.poolDepth ∧ a.wire.length ≤ a.sendDepth

/-- Submit a source frame to the encoder. A full pool drops the newest frame
rather than growing, which is what keeps live memory bounded. -/
def Admit.submit (a : Admit) : Admit :=
  if a.queued < a.poolDepth then { a with queued := a.queued + 1 } else a

/-- Offer one encoded frame's fragments to the wire. All of them are taken or
none are: a frame that does not fit is dropped whole. -/
def Admit.offer (a : Admit) (frags : List Fragment) : Admit :=
  if a.wire.length + frags.length ≤ a.sendDepth then
    { a with queued := a.queued - 1, wire := a.wire ++ frags }
  else
    { a with queued := a.queued - 1 }

def Admit.drain (a : Admit) : Admit :=
  { a with wire := a.wire.drop 1 }

theorem submit_wf {a : Admit} (h : a.wellFormed) : a.submit.wellFormed := by
  unfold Admit.wellFormed at h
  unfold Admit.wellFormed Admit.submit
  split
  · exact ⟨by dsimp only; omega, by dsimp only; exact h.2⟩
  · exact h

/-- No half-sent frame: `offer` either takes every fragment of the frame or
leaves the wire untouched. A partial frame is pure waste of the scarcest
resource, and a decoder can never use one. -/
theorem offer_all_or_nothing (a : Admit) (frags : List Fragment) :
    (a.offer frags).wire = a.wire ++ frags ∨ (a.offer frags).wire = a.wire := by
  unfold Admit.offer
  split
  · exact Or.inl rfl
  · exact Or.inr rfl

theorem offer_wf {a : Admit} (h : a.wellFormed) (frags : List Fragment) :
    (a.offer frags).wellFormed := by
  unfold Admit.wellFormed at h
  unfold Admit.wellFormed Admit.offer
  split
  · rename_i hfit
    refine ⟨?_, ?_⟩
    · dsimp only; omega
    · dsimp only; simp only [List.length_append]; omega
  · exact ⟨by dsimp only; omega, by dsimp only; exact h.2⟩

/-- Live memory is bounded by the two declared depths, whatever the arrival
pattern. This is the property a sustained network stall would otherwise break. -/
theorem live_bounded {a : Admit} (h : a.wellFormed) :
    a.queued + a.wire.length ≤ a.poolDepth + a.sendDepth := by
  unfold Admit.wellFormed at h
  omega

/-- When the wire has room for the whole frame, the frame is taken -- the drop
branch is unreachable. Paired with `offer_all_or_nothing` this pins both sides
of the admission decision. -/
theorem offer_fits {a : Admit} (frags : List Fragment)
    (hw : a.wire.length + frags.length ≤ a.sendDepth) :
    (a.offer frags).wire = a.wire ++ frags := by
  unfold Admit.offer
  split
  · rfl
  · exact absurd hw (by assumption)

/-- The wire always drains: a non-empty send queue strictly shrinks. There is
no state in which the sender holds fragments it can never let go of. -/
theorem drain_progress {a : Admit} (h : 0 < a.wire.length) :
    a.drain.wire.length < a.wire.length := by
  unfold Admit.drain
  simp only [List.length_drop]
  omega

end PixelStream
