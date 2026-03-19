// InstallScmRepl.csx
//
// Unified installer for GML Scheme REPL into Stoneshard.
//
// This script performs four phases:
//   1. Import scm_bundle.gml            (the Scheme interpreter)
//   2. Patch intra-bundle bytecode       (@@This@@+push+callv → direct call.i)
//   3. Create o_scm_repl game object + import event scripts + inject init
//      (second import pass — compiler sees patched bundle functions)
//
// Prerequisites:
//   - Game data (data.win) loaded in UMT
//   - scm_bundle.gml built:  python gml_scheme/bundle.py
//
// After running this script, save the data file in UMT.

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using UndertaleModLib.Models;

EnsureDataLoaded();

// ── Paths ───────────────────────────────────────────────────────────────

string scriptDir     = Path.GetDirectoryName(ScriptPath);
string gmlSchemeRoot = Path.GetFullPath(Path.Combine(scriptDir, ".."));
string bundlePath    = Path.Combine(gmlSchemeRoot, "build", "scm_bundle.gml");

// ── Constants ───────────────────────────────────────────────────────────

const string BUNDLE_NAME    = "scm_bundle";
const string OBJ_NAME       = "o_scm_repl";
const string INIT_CODE_NAME = "gml_GlobalScript_scr_sessionDataInit";

// ═════════════════════════════════════════════════════════════════════════
// Phase 0 — Pre-flight
// ═════════════════════════════════════════════════════════════════════════

if (!File.Exists(bundlePath))
    throw new ScriptException(
        $"scm_bundle.gml not found at:\n  {bundlePath}\n" +
        "Run  python gml_scheme/bundle.py  first.");

string bundleSource = File.ReadAllText(bundlePath);

// ─── Decompile scr_sessionDataInit (before any modifications) ───────

UndertaleCode initCode = Data.Code.ByName(INIT_CODE_NAME);
if (initCode == null)
    throw new ScriptException($"Code entry '{INIT_CODE_NAME}' not found in game data.");

string initSource = GetDecompiledText(initCode);
// Normalize line endings for reliable string matching
initSource = initSource.Replace("\r\n", "\n").Replace("\r", "\n");

// Check idempotency — skip injection if already present
bool needsInjection = !initSource.Contains(OBJ_NAME);
if (needsInjection)
{
    // Match the exact decompiler output for the console_controller block
    // (UMT decompiler emits brace-less single-line if)
    string anchor =
        "    if (!instance_exists(o_console_controller))\n" +
        "        instance_create_depth(-50, -50, 0, o_console_controller);";

    if (!initSource.Contains(anchor))
        throw new ScriptException(
            "Cannot locate o_console_controller block in scr_sessionDataInit.\n" +
            "Decompiler output may have changed. Manual injection required.\n" +
            "Expected anchor:\n" + anchor);

    string replBlock =
        "    if (!instance_exists(" + OBJ_NAME + "))\n" +
        "        instance_create_depth(-50, -50, 0, " + OBJ_NAME + ");";

    initSource = initSource.Replace(anchor, anchor + "\n" + replBlock);
}

ScriptMessage("Phase 0: Pre-flight checks passed.");

// ═════════════════════════════════════════════════════════════════════════
// Phase 1 — Import scm_bundle only
// ═════════════════════════════════════════════════════════════════════════
//
// Import the bundle first so Phase 2 can patch its bytecode.
// Event scripts are imported separately in Phase 3 (second pass) so the
// compiler can resolve scm_repl_*() against the already-registered
// child functions.

{
    var importGroup = new UndertaleModLib.Compiler.CodeImportGroup(Data)
    {
        AutoCreateAssets = true
    };
    importGroup.QueueReplace(BUNDLE_NAME, bundleSource);
    importGroup.Import();
}

ScriptMessage("Phase 1: scm_bundle imported.");

// ═════════════════════════════════════════════════════════════════════════
// Phase 2 — Patch scm_bundle bytecode
// ═════════════════════════════════════════════════════════════════════════
//
// The GML compiler resolves intra-bundle function calls as:
//
//   call.i  @@This@@(argc=0)     ─┐
//   push.v  stacktop.scm_xxx     ─┤  3 instructions (wrong!)
//   callv.v N                     ─┘
//
// At runtime "stacktop.scm_xxx" doesn't exist → crash.
//
// Patch: replace with a single
//   call.i  gml_Script_scm_xxx_scm_bundle(argc=N)

UndertaleCode bundleCode = Data.Code.ByName(BUNDLE_NAME);
if (bundleCode == null)
    throw new ScriptException("scm_bundle code entry missing after import.");

// Build function lookup:  "scm_xxx" → UndertaleFunction
const string FN_PREFIX = "gml_Script_";
string fnSuffix = "_" + BUNDLE_NAME;

var funcLookup = new Dictionary<string, UndertaleFunction>();
foreach (UndertaleCode child in bundleCode.ChildEntries)
{
    string n = child.Name.Content;
    if (!n.StartsWith(FN_PREFIX) || !n.EndsWith(fnSuffix))
        continue;

    string funcName = n.Substring(
        FN_PREFIX.Length,
        n.Length - FN_PREFIX.Length - fnSuffix.Length);

    UndertaleFunction func = Data.Functions.ByName(n);
    if (func != null)
        funcLookup[funcName] = func;
}

ScriptMessage($"Phase 2: Mapped {funcLookup.Count} callable functions, patching...");

// After CodeImportGroup.Import(), the parent code entry contains ALL
// instructions (child entries have empty instruction lists because
// UndertaleCode.Replace() is a no-op for child entries).
// Therefore, only patch the parent entry.

int totalPatched = 0;
int totalSkipped = 0;
var patchErrors  = new List<string>();

{
    var insts = bundleCode.Instructions;
    // Walk backwards so removals don't shift unprocessed indices
    for (int i = insts.Count - 3; i >= 0; i--)
    {
        // ── Pattern match ───────────────────────────────────────────
        // [i]   Call @@This@@   (opcode 0xD9, argc=0)
        // [i+1] Push scm_*     (opcode 0xC0, stacktop variable ref)
        // [i+2] CallV          (opcode 0x99, argc=N)
        if (insts[i].Kind != UndertaleInstruction.Opcode.Call)
            continue;
        if (insts[i].ValueFunction?.Name?.Content != "@@This@@")
            continue;

        if (insts[i + 1].Kind != UndertaleInstruction.Opcode.Push)
            continue;
        string varName = insts[i + 1].ValueVariable?.Name?.Content;
        if (varName == null || !varName.StartsWith("scm_"))
            continue;

        if (insts[i + 2].Kind != UndertaleInstruction.Opcode.CallV)
            continue;

        if (!funcLookup.TryGetValue(varName, out UndertaleFunction targetFunc))
        {
            patchErrors.Add($"  {bundleCode.Name.Content}: no function for '{varName}'");
            totalSkipped++;
            continue;
        }

        int argc = insts[i + 2].Extra;  // CallV stores arg count in Extra

        // ── Fix jump offsets ────────────────────────────────────────
        // Instruction sizes (in 4-byte units):
        //   Call  = 2   (opcode word + function ref)
        //   Push  = 2   (opcode word + variable ref)
        //   CallV = 1   (opcode word only)
        //
        // We keep inst[i] (replaced, same size 2) and remove inst[i+1..i+2].
        // Removed size = 2 + 1 = 3 units.

        uint inst0Size   = insts[i].CalculateInstructionSize();
        uint removedSize = insts[i + 1].CalculateInstructionSize()
                         + insts[i + 2].CalculateInstructionSize();

        // Compute address (in units) of inst[i]
        uint inst0Addr = 0;
        for (int j = 0; j < i; j++)
            inst0Addr += insts[j].CalculateInstructionSize();

        uint removeStart = inst0Addr + inst0Size;          // first removed byte
        uint removeEnd   = removeStart + removedSize;      // exclusive

        // Scan ALL instructions and adjust goto/branch offsets
        uint scanAddr = 0;
        for (int j = 0; j < insts.Count; j++)
        {
            var s = insts[j];
            if (UndertaleInstruction.GetInstructionType(s.Kind)
                == UndertaleInstruction.InstructionType.GotoInstruction
                // PopEnv exit magic is a sentinel (JumpOffset = -1048576),
                // not a real branch target — must never be adjusted.
                && !(s.Kind == UndertaleInstruction.Opcode.PopEnv
                     && s.JumpOffsetPopenvExitMagic))
            {
                uint jumpTarget = (uint)((int)scanAddr + s.JumpOffset);

                if (scanAddr < removeStart && jumpTarget > removeStart)
                {
                    // Forward jump crosses removed region → shrink
                    s.JumpOffset -= (int)removedSize;
                }
                else if (scanAddr >= removeEnd && jumpTarget < removeStart)
                {
                    // Backward jump crosses removed region → grow (less negative)
                    s.JumpOffset += (int)removedSize;
                }
            }
            scanAddr += s.CalculateInstructionSize();
        }

        // ── Replace instructions ────────────────────────────────────
        insts[i] = new UndertaleInstruction()
        {
            Kind           = UndertaleInstruction.Opcode.Call,
            Type1          = UndertaleInstruction.DataType.Int32,
            ArgumentsCount = (ushort)argc,
            ValueFunction  = targetFunc
        };

        // Remove the push + callv (higher index first!)
        insts.RemoveAt(i + 2);
        insts.RemoveAt(i + 1);

        // Update child entry offsets — Offset is in BYTES, removeStart in words
        uint removeStartBytes = removeStart * 4;
        uint removedBytes     = removedSize * 4;
        foreach (var child in bundleCode.ChildEntries)
        {
            if (child.Offset > removeStartBytes)
                child.Offset -= removedBytes;
        }

        totalPatched++;
    }

    bundleCode.UpdateLength();
}

// ── Register scm_bundle in GlobalInitScripts ────────────────────────────
// The compiler needs the bundle in GlobalInitScripts to resolve its child
// functions (scm_repl_create, etc.) when compiling event code below.

if (!Data.GlobalInitScripts.Any(g => g.Code == bundleCode))
{
    Data.GlobalInitScripts.Add(new UndertaleGlobalInit()
    {
        Code = bundleCode
    });
}

ScriptMessage("Phase 2b: scm_bundle registered in GlobalInitScripts.");

// ═════════════════════════════════════════════════════════════════════════
// Phase 3 — Create game object + import events & init (second pass)
// ═════════════════════════════════════════════════════════════════════════
//
// Imported AFTER patching so the compiler resolves scm_repl_*() calls
// against the now-registered child functions (direct call.i, no @@This@@).

if (Data.GameObjects.ByName(OBJ_NAME) == null)
{
    Data.GameObjects.Add(new UndertaleGameObject()
    {
        Name = Data.Strings.MakeString(OBJ_NAME)
    });
}

{
    var importGroup2 = new UndertaleModLib.Compiler.CodeImportGroup(Data)
    {
        AutoCreateAssets = true
    };

    importGroup2.QueueReplace($"gml_Object_{OBJ_NAME}_Create_0",  "scm_repl_create();");
    importGroup2.QueueReplace($"gml_Object_{OBJ_NAME}_Step_0",    "scm_repl_step();");
    importGroup2.QueueReplace($"gml_Object_{OBJ_NAME}_Draw_64",   "scm_repl_draw();");
    importGroup2.QueueReplace($"gml_Object_{OBJ_NAME}_Destroy_0", "scm_repl_destroy();");

    if (needsInjection)
        importGroup2.QueueReplace(INIT_CODE_NAME, initSource);

    importGroup2.Import();
}

ScriptMessage("Phase 3: Game object + events + init imported.");

// ═════════════════════════════════════════════════════════════════════════
// Report
// ═════════════════════════════════════════════════════════════════════════

string report =
    $"InstallScmRepl complete.\n\n" +
    $"  Bundle:    {BUNDLE_NAME} ({bundleCode.ChildEntries.Count} child entries)\n" +
    $"  Patched:   {totalPatched} intra-bundle call sites\n" +
    $"  Skipped:   {totalSkipped}\n" +
    $"  Object:    {OBJ_NAME} (Create / Step / Draw GUI / Destroy)\n" +
    $"  Init:      {(needsInjection ? "injected" : "already present")}\n\n" +
    "Remember to save the data file!";

if (patchErrors.Count > 0)
    report += "\n\nPatch warnings:\n" + string.Join("\n", patchErrors);

ScriptMessage(report);
