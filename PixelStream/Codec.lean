-- SPDX-License-Identifier: Apache-2.0 OR MIT

namespace PixelStream

/-- A group-of-pictures structure: which earlier frames each frame needs.
Dependencies point backwards, which is what makes decodability decidable. -/
structure Gop where
  deps : Nat → List Nat
  backwards : ∀ n, ∀ d ∈ deps n, d < n

/-- Intra-only: every frame stands alone. CineForm is this. -/
def intra : Gop where
  deps := fun _ => []
  backwards := by intro n d hd; simp at hd

/-- IPPP: each frame needs its immediate predecessor. -/
def ippp : Gop where
  deps := fun n => if n = 0 then [] else [n - 1]
  backwards := by
    intro n d hd
    split at hd
    · simp at hd
    · rename_i hne
      simp only [List.mem_singleton] at hd
      omega

def Presentable (g : Gop) (present : Nat → Bool) (n : Nat) : Prop :=
  present n = true ∧ ∀ d ∈ g.deps n, present d = true

/-- The admission test the reassembler runs before presenting a frame. -/
def admitFrame (g : Gop) (present : Nat → Bool) (n : Nat) : Bool :=
  present n && (g.deps n).all present

/-- The load-bearing theorem, and it holds for every GOP structure: a frame is
never presented when a declared dependency was dropped. -/
theorem admitFrame_sound {g : Gop} {present : Nat → Bool} {n : Nat}
    (h : admitFrame g present n = true) : Presentable g present n := by
  unfold admitFrame at h
  rw [Bool.and_eq_true] at h
  exact ⟨h.1, fun d hd => List.all_eq_true.mp h.2 d hd⟩

theorem admitFrame_complete {g : Gop} {present : Nat → Bool} {n : Nat}
    (h : Presentable g present n) : admitFrame g present n = true := by
  unfold admitFrame
  rw [Bool.and_eq_true]
  exact ⟨h.1, List.all_eq_true.mpr h.2⟩

/-- The intra instance is trivial, and saying so is the point: with CineForm
this theorem does no work. It earns its place only when the codec RFD picks an
inter-frame codec, where `ippp` below is already covered. -/
theorem intra_presentable {present : Nat → Bool} {n : Nat} :
    Presentable intra present n ↔ present n = true := by
  unfold Presentable intra
  simp

theorem ippp_presentable {present : Nat → Bool} {n : Nat} (hn : n ≠ 0) :
    Presentable ippp present n ↔ (present n = true ∧ present (n - 1) = true) := by
  unfold Presentable ippp
  simp [hn]

end PixelStream
