// ExportMeta.csx — Export game asset metadata for GML Scheme REPL
//
// Exports to gml_scheme/data/meta/:
//   objects.json    — ["o_player", "o_enemy_goblin", ...]
//   obj_tree.json   — {"o_enemy_base": ["o_enemy_goblin", ...], ...}
//   sprites.json    — ["spr_player_idle", ...]
//   sounds.json     — ["snd_hit_1", ...]
//   rooms.json      — ["rm_tavern", ...]
//   scripts.json    — ["scr_damage", ...] (legacy scripts: asset_get_index + script_execute)
//   functions.json  — ["animated_tile_add", ...] (modern function(){} declarations: direct call)
//
// Usage:
//   UndertaleModCli.exe load data.win -s ExportMeta.csx
//
// The JSON files are consumed by codegen_meta.py to generate
// scm_meta.gml (embedded name arrays for discovery + tab completion).

using System;
using System.IO;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;
using System.Text.Encodings.Web;

EnsureDataLoaded();

if (Data.IsYYC())
{
    ScriptError("The opened game uses YYC: no code is available.");
    return;
}

// ── Output path: gml_scheme/data/meta/ ────────────────────────────
string scriptDir = Path.GetDirectoryName(ScriptPath);
string gmlSchemeRoot = Path.GetFullPath(Path.Combine(scriptDir, ".."));
string outputFolder = Path.Combine(gmlSchemeRoot, "data", "meta");

if (!Directory.Exists(outputFolder))
    Directory.CreateDirectory(outputFolder);

var jsonOptions = new JsonSerializerOptions
{
    WriteIndented = true,
    Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping
};

int exported = 0;

// ── 1. Object names (sorted) ─────────────────────────────────────
{
    var names = Data.GameObjects
        .Select(o => o.Name.Content)
        .OrderBy(n => n)
        .ToList();

    string path = Path.Combine(outputFolder, "objects.json");
    File.WriteAllText(path, JsonSerializer.Serialize(names, jsonOptions));
    ScriptMessage($"  objects: {names.Count}");
    exported++;
}

// ── 2. Object inheritance tree ───────────────────────────────────
{
    var tree = Data.GameObjects
        .Where(o => o.ParentId is not null)
        .GroupBy(o => o.ParentId.Name.Content)
        .ToDictionary(
            g => g.Key,
            g => g.Select(o => o.Name.Content).OrderBy(n => n).ToList()
        );

    var sorted = new SortedDictionary<string, List<string>>(tree);

    string path = Path.Combine(outputFolder, "obj_tree.json");
    File.WriteAllText(path, JsonSerializer.Serialize(sorted, jsonOptions));
    ScriptMessage($"  obj_tree: {sorted.Count} parents");
    exported++;
}

// ── 3. Sprite names (sorted) ────────────────────────────────────
{
    var names = Data.Sprites
        .Select(s => s.Name.Content)
        .OrderBy(n => n)
        .ToList();

    string path = Path.Combine(outputFolder, "sprites.json");
    File.WriteAllText(path, JsonSerializer.Serialize(names, jsonOptions));
    ScriptMessage($"  sprites: {names.Count}");
    exported++;
}

// ── 4. Sound names (sorted) ─────────────────────────────────────
{
    var names = Data.Sounds
        .Select(s => s.Name.Content)
        .OrderBy(n => n)
        .ToList();

    string path = Path.Combine(outputFolder, "sounds.json");
    File.WriteAllText(path, JsonSerializer.Serialize(names, jsonOptions));
    ScriptMessage($"  sounds: {names.Count}");
    exported++;
}

// ── 5. Room names (sorted) ──────────────────────────────────────
{
    var names = Data.Rooms
        .Select(r => r.Name.Content)
        .OrderBy(n => n)
        .ToList();

    string path = Path.Combine(outputFolder, "rooms.json");
    File.WriteAllText(path, JsonSerializer.Serialize(names, jsonOptions));
    ScriptMessage($"  rooms: {names.Count}");
    exported++;
}

// ── 6. Legacy scripts vs modern functions ───────────────────────
//
// GMS2.3+ (bytecode 17) has two kinds of callable:
//   Legacy scripts:  Code "gml_Script_<name>" with ParentEntry == null
//                    The Code entry IS the function body itself.
//   Modern functions: Code "gml_Script_<name>" with ParentEntry != null
//                    The Code is a child of a container script;
//                    actual implementation lives in the parent.
//
// We use Code.ParentEntry to distinguish: null → legacy, non-null → modern.
{
    var codePrefix = "gml_Script_";

    var scripts = new List<string>();    // legacy scripts (ParentEntry == null)
    var functions = new List<string>();  // modern function(){} (ParentEntry != null)
    var seen = new HashSet<string>();

    foreach (var code in Data.Code)
    {
        var name = code.Name.Content;
        if (!name.StartsWith(codePrefix)) continue;

        var shortName = name.Substring(codePrefix.Length);

        // Filter noise
        if (shortName.StartsWith("__")           ||
            shortName.StartsWith("_COPY_")       ||
            shortName.StartsWith("anon_")        ||
            shortName.Contains("@")              ||
            shortName.Contains("_gml_Object_")   ||
            shortName.Contains("_gml_GlobalScript_"))
            continue;

        if (!seen.Add(shortName)) continue;  // deduplicate

        if (code.ParentEntry != null)
            functions.Add(shortName);
        else
            scripts.Add(shortName);
    }

    scripts.Sort();
    functions.Sort();

    // --- Write scripts.json ---
    {
        string path = Path.Combine(outputFolder, "scripts.json");
        File.WriteAllText(path, JsonSerializer.Serialize(scripts, jsonOptions));
        ScriptMessage($"  scripts: {scripts.Count} (legacy)");
        exported++;
    }

    // --- Write functions.json ---
    {
        string path = Path.Combine(outputFolder, "functions.json");
        File.WriteAllText(path, JsonSerializer.Serialize(functions, jsonOptions));
        ScriptMessage($"  functions: {functions.Count} (modern)");
        exported++;
    }
}

ScriptMessage($"\nExported {exported} meta files to:\n{outputFolder}");
