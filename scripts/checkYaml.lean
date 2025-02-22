/-
Copyright (c) 2023 Eric Wieser. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Eric Wieser
-/

import Mathlib.Tactic.Basic

/-! # Script to check `undergrad.yaml`, `overview.yaml`, and `100.yaml`

This assumes `yaml_check.py` has first translated these to `json` files.

It verifies that the referenced declarations exist.
-/

open IO.FS Lean Lean.Elab
open Lean Core Elab Command Std.Tactic.Lint

abbrev DBFile := Array (String × Name)

def readJsonFile (α) [FromJson α] (path : System.FilePath) : IO α := do
  let _ : MonadExceptOf String IO := ⟨throw ∘ IO.userError, fun x _ => x⟩
  liftExcept <| fromJson? <|← liftExcept <| Json.parse <|← IO.FS.readFile path

def databases : List (String × String) := [
  ("undergrad.json", "Entries in `docs/undergrad.yaml` refer to declarations that don't exist. Please correct the following:"),
  ("overview.json", "Entries in `docs/overview.yaml` refer to declarations that don't exist. Please correct the following:"),
  ("100.json", "Entries in `docs/100.yaml` refer to declarations that don't exist. Please correct the following:")
]

def processDb (decls : ConstMap) : String × String → IO Bool
| (file, msg) => do
  let lines := ← readJsonFile DBFile file
  let missing := lines.filter (fun l => !(decls.contains l.2))
  if 0 < missing.size then
    IO.println msg
    for p in missing do
      IO.println s!"  {p.1}: {p.2}"
    IO.println ""
    return true
  else
    return false

open System in
instance : ToExpr FilePath where
  toTypeExpr := mkConst ``FilePath
  toExpr path := mkApp (mkConst ``FilePath.mk) (toExpr path.1)

elab "compileTimeSearchPath" : term =>
  return toExpr (← searchPathRef.get)

unsafe def main : IO Unit := do
  searchPathRef.set compileTimeSearchPath
  withImportModules [{module := `Mathlib}] {} (trustLevel := 1024) fun env =>
    let ctx := {fileName := "", fileMap := default}
    let state := {env}
    Prod.fst <$> (CoreM.toIO · ctx state) do
      let decls := env.constants
      let results ← databases.mapM (fun p => processDb decls p)
      if results.any id then
        IO.Process.exit 1
