-- SPDX-License-Identifier: Apache-2.0 OR MIT

import PixelStream.Witness
import PlausibleWitnessDag

open PixelStream PlausibleWitnessDag

/-- How far the deterministic readback looks before it calls a negative clean.
`resolve` decides the outcome from the readback rather than from `certify`'s
return, so this number -- not the ladder's `finBound` -- is the real width of
the search, and it is stated rather than implied. -/
private def searchWidth : Nat := 4000

/-- A witness here is a counter-example, so `found` is the failing outcome for
the real reassembler and the expected one for the broken control. -/
private def query (name : String) (out : List Fragment → List Frame) :
    IO (Nat × TraceEntry) := do
  let candidate : Level → Nat → Bool := fun _ c => violates out c
  let readback : Nat → Readback (Option Nat) := fun steps =>
    match firstViolation out steps with
    | some w => { value := some w, found := true, witnessIdx := w, budgetHit := false }
    | none => { value := none, found := false, budgetHit := (firstViolation out searchWidth).isSome }
  let (_, lvl, trace) ← resolve name candidate readback
  pure (lvl, trace)

def main : IO Unit := do
  let (lvlGood, tGood) ← query "reassembler violates monotonicity / provenance / uniqueness" goodOut
  IO.println s!"  real      L{lvlGood}  {repr tGood.outcome}"
  let (lvlBroken, tBroken) ← query "control: emit-on-first-fragment violates them" brokenOut
  IO.println s!"  control   L{lvlBroken}  {repr tBroken.outcome}"

  -- A budget hit is not a clean negative, and must not read as one.
  match tGood.outcome with
  | .provablyNone =>
      IO.println s!"  searched {searchWidth} candidate traces, no counter-example"
  | .found w => throw <| IO.userError s!"counter-example found at candidate {w}"
  | .budgetHit => throw <| IO.userError "search ran out of budget; that is not a pass"

  -- The search is worth nothing unless it can find a real defect.
  match tBroken.outcome with
  | .found _ => IO.println "ok: no counter-example for the reassembler, and the control was caught"
  | _ => throw <| IO.userError "the control was not caught, so this search proves nothing"
