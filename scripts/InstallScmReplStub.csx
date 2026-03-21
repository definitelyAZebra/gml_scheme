// InstallScmReplStub.csx
//
// Alternative installer for GML Scheme REPL — "stub pre-registration" approach.
//
// Instead of patching bytecode after import, this script pre-registers all
// function names by importing empty stubs first, then replaces them with the
// real bundle.  The hypothesis is that the GML compiler will emit direct
// call.i instructions (instead of @@This@@+push+callv) when function names
// are already known in Data.Functions.
//
// Phases:
//   0. Pre-flight (same as InstallScmRepl.csx)
//   1. Import scm_stubs.gml as scm_bundle (registers function names)
//   2. Import real scm_bundle.gml as scm_bundle (QueueReplace)
//   3. Create game object + import events + inject init
//
// NO bytecode patching is performed.

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using UndertaleModLib.Models;

EnsureDataLoaded();

// ── Paths ───────────────────────────────────────────────────────────────
// All build artifacts are expected next to this script.

string scriptDir  = Path.GetDirectoryName(ScriptPath);
string bundlePath = Path.Combine(scriptDir, "scm_bundle.gml");
string stubsPath  = Path.Combine(scriptDir, "scm_stubs.gml");
string fontPath   = Path.Combine(scriptDir, "monof55.ttf");
string cjkFontPath = Path.Combine(scriptDir, "HanyiSentyYongleEncyclopedia-2020.ttf");

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

if (!File.Exists(stubsPath))
    throw new ScriptException(
        $"scm_stubs.gml not found at:\n  {stubsPath}\n" +
        "Generate stubs first.");

string bundleSource = File.ReadAllText(bundlePath);
string stubsSource  = File.ReadAllText(stubsPath);

// ─── Decompile scr_sessionDataInit (before any modifications) ───────

UndertaleCode initCode = Data.Code.ByName(INIT_CODE_NAME);
if (initCode == null)
    throw new ScriptException($"Code entry '{INIT_CODE_NAME}' not found in game data.");

string initSource = GetDecompiledText(initCode);
initSource = initSource.Replace("\r\n", "\n").Replace("\r", "\n");

bool needsInjection = !initSource.Contains(OBJ_NAME);
if (needsInjection)
{
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
// Phase 1 — Import stubs (pre-register function names)
// ═════════════════════════════════════════════════════════════════════════
//
// Import empty function stubs so that all scm_* function names are
// registered in Data.Functions before the real bundle is compiled.

{
    var importGroup = new UndertaleModLib.Compiler.CodeImportGroup(Data)
    {
        AutoCreateAssets = true
    };
    importGroup.QueueReplace(BUNDLE_NAME, stubsSource);
    importGroup.Import();
}

UndertaleCode bundleCode = Data.Code.ByName(BUNDLE_NAME);
int stubChildCount = bundleCode?.ChildEntries?.Count ?? 0;
ScriptMessage($"Phase 1: Stubs imported ({stubChildCount} functions registered).");

// ── Register scm_bundle in GlobalInitScripts ────────────────────────────
// Register BEFORE importing the real bundle so the compiler can resolve
// child functions during compilation of intra-bundle calls.

if (!Data.GlobalInitScripts.Any(g => g.Code == bundleCode))
{
    Data.GlobalInitScripts.Add(new UndertaleGlobalInit()
    {
        Code = bundleCode
    });
}

ScriptMessage("Phase 1b: scm_bundle registered in GlobalInitScripts.");

// ═════════════════════════════════════════════════════════════════════════
// Phase 2 — Import real bundle (replaces stubs)
// ═════════════════════════════════════════════════════════════════════════
//
// Since function names are already in Data.Functions AND the bundle is
// registered in GlobalInitScripts, the compiler should resolve intra-bundle
// calls as direct call.i instead of @@This@@+push+callv.

{
    var importGroup2 = new UndertaleModLib.Compiler.CodeImportGroup(Data)
    {
        AutoCreateAssets = true
    };
    importGroup2.QueueReplace(BUNDLE_NAME, bundleSource);
    importGroup2.Import();
}

int realChildCount = bundleCode?.ChildEntries?.Count ?? 0;
ScriptMessage($"Phase 2: Real bundle imported ({realChildCount} child entries).");

// ═════════════════════════════════════════════════════════════════════════
// Phase 3 — Create game object + import events & init
// ═════════════════════════════════════════════════════════════════════════

var obj = Data.GameObjects.ByName(OBJ_NAME);
if (obj == null)
{
    obj = new UndertaleGameObject()
    {
        Name = Data.Strings.MakeString(OBJ_NAME)
    };
    Data.GameObjects.Add(obj);
}
obj.Persistent = true;

{
    var importGroup3 = new UndertaleModLib.Compiler.CodeImportGroup(Data)
    {
        AutoCreateAssets = true
    };

    importGroup3.QueueReplace($"gml_Object_{OBJ_NAME}_Create_0",       "scm_repl_create();");
    importGroup3.QueueReplace($"gml_Object_{OBJ_NAME}_Step_0",         "scm_repl_step();");
    importGroup3.QueueReplace($"gml_Object_{OBJ_NAME}_Draw_64",        "scm_repl_draw();");
    importGroup3.QueueReplace($"gml_Object_{OBJ_NAME}_KeyPress_112",   "scm_repl_toggle();");  // vk_f1 = 112
    importGroup3.QueueReplace($"gml_Object_{OBJ_NAME}_Destroy_0",      "scm_repl_destroy();");

    if (needsInjection)
        importGroup3.QueueReplace(INIT_CODE_NAME, initSource);

    importGroup3.Import();
}

ScriptMessage("Phase 3: Game object + events + init imported.");

// ═════════════════════════════════════════════════════════════════════════
// Report
// ═════════════════════════════════════════════════════════════════════════

// ═════════════════════════════════════════════════════════════════════════
// Phase 4 — Copy fonts to game directory
// ═════════════════════════════════════════════════════════════════════════
//
// font_add() in GML looks for files relative to the game's working
// directory (same folder as data.win).  We copy both .ttf files there.

string gameDir = Path.GetDirectoryName(FilePath);
bool fontCopied = false;
bool cjkFontCopied = false;

// ASCII monospace font
if (File.Exists(fontPath))
{
    string destPath = Path.Combine(gameDir, "monof55.ttf");
    if (!File.Exists(destPath))
    {
        File.Copy(fontPath, destPath);
        fontCopied = true;
        ScriptMessage($"Phase 4: Copied monof55.ttf → {destPath}");
    }
    else
    {
        ScriptMessage("Phase 4: monof55.ttf already exists in game directory, skipped.");
    }
}
else
{
    ScriptMessage($"Phase 4: monof55.ttf not found at {fontPath}, skipping.");
}

// CJK fallback font
if (File.Exists(cjkFontPath))
{
    string destPath = Path.Combine(gameDir, "HanyiSentyYongleEncyclopedia-2020.ttf");
    if (!File.Exists(destPath))
    {
        File.Copy(cjkFontPath, destPath);
        cjkFontCopied = true;
        ScriptMessage($"Phase 4: Copied CJK font → {destPath}");
    }
    else
    {
        ScriptMessage("Phase 4: CJK font already exists in game directory, skipped.");
    }
}
else
{
    ScriptMessage($"Phase 4: CJK font not found at {cjkFontPath}, skipping.");
}

// ═════════════════════════════════════════════════════════════════════════
// Phase 5 — Copy data files (metadata + tries) to game directory
// ═════════════════════════════════════════════════════════════════════════
//
// scm_meta_init() loads JSON files via buffer_load("scm_data/...").
// We copy the scm_data/ folder next to data.win.

string srcDataDir  = Path.Combine(scriptDir, "scm_data");
string destDataDir = Path.Combine(gameDir, "scm_data");
int dataCopied = 0;

if (Directory.Exists(srcDataDir))
{
    Directory.CreateDirectory(destDataDir);

    foreach (string srcFile in Directory.GetFiles(srcDataDir, "*.json"))
    {
        string fileName = Path.GetFileName(srcFile);
        string destFile = Path.Combine(destDataDir, fileName);
        File.Copy(srcFile, destFile, overwrite: true);
        dataCopied++;
    }

    ScriptMessage($"Phase 5: Copied {dataCopied} data files → {destDataDir}");
}
else
{
    ScriptMessage($"Phase 5: scm_data/ not found at {srcDataDir}, skipping. Tab completion will not work.");
}

// ═════════════════════════════════════════════════════════════════════════
// Report
// ═════════════════════════════════════════════════════════════════════════

string report =
    $"InstallScmReplStub complete.\n\n" +
    $"  Approach:  Stub pre-registration (no bytecode patching)\n" +
    $"  Bundle:    {BUNDLE_NAME} ({realChildCount} child entries)\n" +
    $"  Object:    {OBJ_NAME} (Create / Step / Draw GUI / KeyPress F1 / Destroy)\n" +
    $"  Init:      {(needsInjection ? "injected" : "already present")}\n" +
    $"  Font:      {(fontCopied ? "copied" : "already present or skipped")}\n" +
    $"  CJK Font:  {(cjkFontCopied ? "copied" : "already present or skipped")}\n\n" +
    "Remember to save the data file!";

ScriptMessage(report);
