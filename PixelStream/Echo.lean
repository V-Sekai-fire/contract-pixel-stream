-- SPDX-License-Identifier: Apache-2.0 OR MIT

import PixelStream.Wire

namespace PixelStream

/-- The server's side of the echo: the highest client input consumed so far,
and the frames rendered from it. -/
structure Echo where
  consumed : Nat
  emitted : List Frame
  deriving Repr, Inhabited

def Echo.wellFormed (e : Echo) : Prop :=
  ∀ f ∈ e.emitted, f.echoedInputSeq ≤ e.consumed

def Echo.consume (e : Echo) (n : Nat) : Echo :=
  { e with consumed := max e.consumed n }

/-- Render stamps the frame with the input actually consumed, never a later one. -/
def Echo.render (e : Echo) (seq : Nat) (payload : List UInt8) : Echo :=
  { e with emitted := e.emitted ++
      [{ frameSeq := seq, echoedInputSeq := e.consumed, payload := payload }] }

theorem consume_wf {e : Echo} (h : e.wellFormed) (n : Nat) :
    (e.consume n).wellFormed := by
  unfold Echo.wellFormed Echo.consume at *
  intro f hf
  have := h f hf
  dsimp only at hf ⊢
  omega

theorem render_wf {e : Echo} (h : e.wellFormed) (seq : Nat) (payload : List UInt8) :
    (e.render seq payload).wellFormed := by
  unfold Echo.wellFormed Echo.render at *
  intro f hf
  dsimp only at hf ⊢
  rcases List.mem_append.mp hf with hin | hnew
  · exact h f hin
  · simp only [List.mem_singleton] at hnew
    subst hnew
    exact Nat.le_refl _

/-- The client is never shown its own future: an echoed input never exceeds
what the client actually sent. This is what makes the latency measurement
honest rather than a proxy -- the client can compute the true age of the image
it is looking at. -/
theorem echo_le_client {e : Echo} (h : e.wellFormed) {clientMax : Nat}
    (hc : e.consumed ≤ clientMax) {f : Frame} (hf : f ∈ e.emitted) :
    f.echoedInputSeq ≤ clientMax :=
  Nat.le_trans (h f hf) hc

end PixelStream
