// PatchScmBundle.csx
// Run this AFTER ImportGML has compiled scm_bundle.gml.
//
// Problem: The GML compiler resolves intra-bundle function calls as:
//   call.i  @@This@@(argc=0)     // push self struct
//   push.v  builtin.scm_xxx      // lookup function in builtin namespace (WRONG)
//   callv.v N                    // dynamic call with N args
//
// At runtime, "builtin.scm_xxx" doesn't exist → crash.
//
// Fix: Replace the 3-instruction dynamic-call pattern with a single direct call:
//   call.i  gml_Script_scm_xxx_scm_bundle(argc=N)
//
// This works because each `function scm_xxx(){}` inside scm_bundle creates
// a child code entry named `gml_Script_scm_xxx_scm_bundle`.

using System;
using System.Collections.Generic;
using System.Linq;
using UndertaleModLib.Models;

EnsureDataLoaded();

const string BUNDLE_NAME = "scm_bundle";
const string CHILD_PREFIX = "gml_Script_";
const string CHILD_SUFFIX = "_" + BUNDLE_NAME;

// ── Step 1: Find the parent code entry ──────────────────────────────────

UndertaleCode bundleCode = Data.Code.ByName(BUNDLE_NAME);
if (bundleCode == null)
{
    ScriptError($"Code entry '{BUNDLE_NAME}' not found. Did you run ImportGML first?",
                "PatchScmBundle");
    return;
}

// ── Step 2: Build a lookup of child function names ──────────────────────
// Child entries are named  gml_Script_{funcName}_scm_bundle
// We want to map  "scm_xxx"  →  UndertaleFunction for gml_Script_scm_xxx_scm_bundle

var funcLookup = new Dictionary<string, UndertaleFunction>();

// Collect ALL code entries that are children of scm_bundle
// (child entries share bytecode with the parent, but have their own Code entry)
List<UndertaleCode> childEntries = bundleCode.ChildEntries;
ScriptMessage($"Found {childEntries.Count} child entries under '{BUNDLE_NAME}'.");

foreach (UndertaleCode child in childEntries)
{
    string childName = child.Name.Content;  // e.g. "gml_Script_scm_nil_scm_bundle"
    if (!childName.StartsWith(CHILD_PREFIX) || !childName.EndsWith(CHILD_SUFFIX))
        continue;

    // Extract function name: strip prefix and suffix
    string funcName = childName.Substring(
        CHILD_PREFIX.Length,
        childName.Length - CHILD_PREFIX.Length - CHILD_SUFFIX.Length
    );

    // Find (or verify) the UndertaleFunction for this child entry
    UndertaleFunction func = Data.Functions.ByName(childName);
    if (func == null)
    {
        ScriptMessage($"WARNING: No UndertaleFunction found for '{childName}', skipping.");
        continue;
    }

    funcLookup[funcName] = func;
}

ScriptMessage($"Mapped {funcLookup.Count} callable functions.");

// ── Step 3: Patch all child entries ─────────────────────────────────────
// The pattern to find (3 instructions):
//   [i]   call.i   @@This@@(argc=0)     Kind=Call,     ValueFunction.Name="@@This@@"
//   [i+1] push.v   builtin.scm_xxx      Kind=PushBltn, ValueVariable.Name="scm_xxx"
//   [i+2] callv.v  N                    Kind=CallV,    Extra=N
//
// Replace with 1 instruction:
//   [i]   call.i   gml_Script_scm_xxx_scm_bundle(argc=N)

int totalPatched = 0;
int totalSkipped = 0;
var patchErrors = new List<string>();

// We need to patch child entries (they contain the actual function bodies)
// The parent entry itself also has instructions (the top-level init code),
// so we patch both parent + children.
var codesToPatch = new List<UndertaleCode> { bundleCode };
codesToPatch.AddRange(childEntries);

foreach (UndertaleCode code in codesToPatch)
{
    var instructions = code.Instructions;
    // Walk backwards so removal doesn't affect iteration
    for (int i = instructions.Count - 3; i >= 0; i--)
    {
        var inst0 = instructions[i];
        var inst1 = instructions[i + 1];
        var inst2 = instructions[i + 2];

        // Match: call.i @@This@@(argc=0)
        if (inst0.Kind != UndertaleInstruction.Opcode.Call)
            continue;
        if (inst0.ValueFunction?.Name?.Content != "@@This@@")
            continue;

        // Match: push.v builtin.scm_xxx  (PushBltn opcode)
        if (inst1.Kind != UndertaleInstruction.Opcode.PushBltn)
            continue;
        string varName = inst1.ValueVariable?.Name?.Content;
        if (varName == null || !varName.StartsWith("scm_"))
            continue;

        // Match: callv.v N
        if (inst2.Kind != UndertaleInstruction.Opcode.CallV)
            continue;

        // Look up the target function
        if (!funcLookup.TryGetValue(varName, out UndertaleFunction targetFunc))
        {
            patchErrors.Add($"  {code.Name.Content}: no function for '{varName}'");
            totalSkipped++;
            continue;
        }

        int argc = inst2.Extra;  // CallV stores arg count in Extra

        // ── Adjust jump offsets ─────────────────────────────────
        // We're removing 2 instructions (inst1 and inst2) and replacing inst0.
        // Total size change = -(inst1.size + inst2.size) in instruction units.
        //
        // inst0 (Call) = 2 units (has ValueFunction)
        // inst1 (PushBltn) = 2 units (has ValueVariable)
        // inst2 (CallV) = 1 unit (SingleTypeInstruction, no variable/function)
        //
        // Original total: 2 + 2 + 1 = 5 units
        // New total: 2 units (single Call instruction)
        // Delta: -3 units

        uint inst0Size = inst0.CalculateInstructionSize();  // 2
        uint inst1Size = inst1.CalculateInstructionSize();  // 2
        uint inst2Size = inst2.CalculateInstructionSize();  // 1
        uint removedSize = inst1Size + inst2Size;           // 3

        // Compute byte address of inst0
        uint inst0Addr = 0;
        for (int j = 0; j < i; j++)
            inst0Addr += instructions[j].CalculateInstructionSize();

        // Address range being removed: from (inst0Addr + inst0Size) to (inst0Addr + inst0Size + removedSize - 1)
        uint removeStart = inst0Addr + inst0Size;
        uint removeEnd = removeStart + removedSize;  // exclusive

        // Fix jump offsets for all goto-family instructions in this code entry
        uint scanAddr = 0;
        for (int j = 0; j < instructions.Count; j++)
        {
            var scanInst = instructions[j];
            if (UndertaleInstruction.GetInstructionType(scanInst.Kind)
                == UndertaleInstruction.InstructionType.GotoInstruction)
            {
                // Jump target address (in instruction units)
                uint targetAddr = (uint)((int)scanAddr + scanInst.JumpOffset);

                if (scanAddr < removeStart && targetAddr > removeStart)
                {
                    // Jump crosses over the removed region → shrink
                    scanInst.JumpOffset -= (int)removedSize;
                }
                else if (scanAddr >= removeEnd && targetAddr < removeStart)
                {
                    // Backward jump crosses over the removed region → grow (less negative)
                    scanInst.JumpOffset += (int)removedSize;
                }
            }
            scanAddr += scanInst.CalculateInstructionSize();
        }

        // ── Replace instructions ────────────────────────────────
        // Replace inst0 in-place with the direct call
        instructions[i] = new UndertaleInstruction()
        {
            Kind = UndertaleInstruction.Opcode.Call,
            Type1 = UndertaleInstruction.DataType.Int32,
            ArgumentsCount = (ushort)argc,
            ValueFunction = targetFunc
        };

        // Remove inst1 and inst2 (the push + callv)
        instructions.RemoveAt(i + 2);
        instructions.RemoveAt(i + 1);

        totalPatched++;
    }

    code.UpdateLength();
}

// ── Step 4: Report ──────────────────────────────────────────────────────
string report = $"PatchScmBundle complete.\n" +
                $"  Patched: {totalPatched} call sites\n" +
                $"  Skipped: {totalSkipped}";
if (patchErrors.Count > 0)
{
    report += $"\n  Errors:\n" + string.Join("\n", patchErrors);
}
ScriptMessage(report);
