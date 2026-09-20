-- SPDX-License-Identifier: Apache-2.0 OR MIT

import PixelStream.Wire

namespace PixelStream

/-- Fragments of one frame seen so far, keyed by index. -/
structure Pending where
  frameSeq : Nat
  fragCount : Nat
  echoedInputSeq : Nat
  slots : List (Nat × List UInt8)
  deriving Repr, Inhabited

def Pending.has (p : Pending) (i : Nat) : Bool :=
  p.slots.any (fun s => s.1 == i)

def Pending.complete (p : Pending) : Bool :=
  (List.range p.fragCount).all p.has

def Pending.assemble (p : Pending) : List UInt8 :=
  (List.range p.fragCount).flatMap
    (fun i => ((p.slots.find? (fun s => s.1 == i)).map (fun s => s.2)).getD [])

def Pending.admit (p : Pending) (f : Fragment) : Pending :=
  if p.has f.fragIndex then p
  else { p with slots := (f.fragIndex, f.payload) :: p.slots }

/-- `lastEmitted` is the newest frame already presented; `capacity` bounds how
many incomplete frames may be held at once. -/
structure State where
  lastEmitted : Option Nat
  pending : List Pending
  capacity : Nat
  deriving Repr, Inhabited

def State.init (capacity : Nat) : State :=
  { lastEmitted := none, pending := [], capacity := capacity }

/-- A fragment is stale when its frame is not newer than the last presented. -/
def State.stale (s : State) (f : Fragment) : Bool :=
  match s.lastEmitted with
  | none => false
  | some l => f.frameSeq ≤ l

def dropOldest (cap : Nat) (ps : List Pending) : List Pending :=
  if ps.length ≤ cap then ps else ps.take cap

def insertFragment (ps : List Pending) (f : Fragment) : List Pending :=
  match ps.find? (fun p => p.frameSeq == f.frameSeq) with
  | some p =>
      (p.admit f) :: ps.filter (fun q => !(q.frameSeq == f.frameSeq))
  | none =>
      ({ frameSeq := f.frameSeq, fragCount := f.fragCount,
         echoedInputSeq := f.echoedInputSeq, slots := [] } : Pending).admit f :: ps

/-- Decide the outcome once the fragment has been filed. Split out of `step`
so the emitting branch is reachable by `split` in the proofs below. -/
def stepFiled (s : State) (ps : List Pending) (f : Fragment) : State × Option Frame :=
  match ps.find? (fun p => p.frameSeq == f.frameSeq) with
  | none => (s, none)
  | some p =>
      if p.complete then
        ({ s with lastEmitted := some p.frameSeq,
                  pending := dropOldest s.capacity
                    (ps.filter (fun q => q.frameSeq > p.frameSeq)) },
         some { frameSeq := p.frameSeq, echoedInputSeq := p.echoedInputSeq,
                payload := p.assemble })
      else
        ({ s with pending := dropOldest s.capacity ps }, none)

/-- One fragment in, at most one frame out. Malformed and stale fragments
change nothing. -/
def step (s : State) (f : Fragment) : State × Option Frame :=
  if !(decide f.wellFormed) then (s, none)
  else if s.stale f then (s, none)
  else stepFiled s (insertFragment s.pending f) f


/-- `dropOldest` is the only way `pending` grows, and it never exceeds the cap. -/
theorem dropOldest_le (cap : Nat) (ps : List Pending) :
    (dropOldest cap ps).length ≤ cap := by
  unfold dropOldest
  split
  · omega
  · rename_i hgt
    simp only [List.length_take]
    omega

theorem stepFiled_capacity {s s' : State} {ps : List Pending} {f : Fragment}
    {o : Option Frame} (h : stepFiled s ps f = (s', o)) : s'.capacity = s.capacity := by
  unfold stepFiled at h
  split at h
  · simp only [Prod.mk.injEq] at h; rw [← h.1]
  · split at h <;> (simp only [Prod.mk.injEq] at h; rw [← h.1])

/-- Bounded buffer: at most `capacity` incomplete frames are ever held, so a
sustained loss burst cannot grow memory without limit. -/
theorem step_pending_bounded (s : State) (f : Fragment)
    (h : s.pending.length ≤ s.capacity) :
    (step s f).1.pending.length ≤ (step s f).1.capacity := by
  unfold step
  split
  · exact h
  · split
    · exact h
    · unfold stepFiled
      split
      · exact h
      · split <;> exact dropOldest_le _ _

end PixelStream

namespace PixelStream

/-- No partial presentation: a complete frame holds every index it declared. -/
theorem complete_has {p : Pending} (h : p.complete = true)
    {i : Nat} (hi : i < p.fragCount) : p.has i = true := by
  unfold Pending.complete at h
  exact List.all_eq_true.mp h i (List.mem_range.mpr hi)

private theorem find?_frameSeq {ps : List Pending} {f : Fragment} {p : Pending}
    (h : ps.find? (fun q => q.frameSeq == f.frameSeq) = some p) :
    p.frameSeq = f.frameSeq := by
  have := List.find?_some h
  simpa using this

/-- An emitted frame was complete, and it is the frame the fragment belonged to. -/
theorem stepFiled_emit_complete {s s' : State} {ps : List Pending} {f : Fragment}
    {fr : Frame} (h : stepFiled s ps f = (s', some fr)) :
    ∃ p : Pending, p.complete = true ∧ p.frameSeq = fr.frameSeq
      ∧ p.frameSeq = f.frameSeq := by
  unfold stepFiled at h
  split at h
  · simp at h
  · rename_i p hfind
    split at h
    · rename_i hc
      refine ⟨p, hc, ?_, find?_frameSeq hfind⟩
      simp only [Prod.mk.injEq, Option.some.injEq] at h
      rw [← h.2]
    · simp at h

/-- The emitted frame becomes the newest presented. -/
theorem stepFiled_emit_sets_last {s s' : State} {ps : List Pending} {f : Fragment}
    {fr : Frame} (h : stepFiled s ps f = (s', some fr)) :
    s'.lastEmitted = some fr.frameSeq := by
  unfold stepFiled at h
  split at h
  · simp at h
  · rename_i p hfind
    split at h
    · simp only [Prod.mk.injEq, Option.some.injEq] at h
      rw [← h.1, ← h.2]
    · simp at h

theorem step_emit_complete {s s' : State} {f : Fragment} {fr : Frame}
    (h : step s f = (s', some fr)) :
    ∃ p : Pending, p.complete = true ∧ p.frameSeq = fr.frameSeq
      ∧ p.frameSeq = f.frameSeq := by
  unfold step at h
  split at h
  · simp at h
  · split at h
    · simp at h
    · exact stepFiled_emit_complete h

theorem step_emit_sets_last {s s' : State} {f : Fragment} {fr : Frame}
    (h : step s f = (s', some fr)) : s'.lastEmitted = some fr.frameSeq := by
  unfold step at h
  split at h
  · simp at h
  · split at h
    · simp at h
    · exact stepFiled_emit_sets_last h

/-- Monotone emit: a frame is presented only if it is newer than the last one
presented, so a late fragment cannot resurrect a stale frame. -/
theorem step_emit_monotone {s s' : State} {f : Fragment} {fr : Frame} {l : Nat}
    (h : step s f = (s', some fr)) (hl : s.lastEmitted = some l) : l < fr.frameSeq := by
  unfold step at h
  split at h
  · simp at h
  · split at h
    · simp at h
    · rename_i hns
      obtain ⟨p, _, hpfr, hpf⟩ := stepFiled_emit_complete h
      have hfresh : ¬ (f.frameSeq ≤ l) := by
        unfold State.stale at hns
        rw [hl] at hns
        simpa using hns
      omega
