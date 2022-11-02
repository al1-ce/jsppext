module modules.preprocess;

import std.conv: to;
import std.regex;
import std.algorithm.searching: startsWith, endsWith, canFind;
import std.stdio: writef, writefln, readln, stdin, stdout;
import std.stdio: writeln, write, File;
import std.path: buildNormalizedPath, absolutePath, isValidPath, dirSeparator, dirName, relativePath, baseName;
import std.file: readText, exists, isFile, mkdirRecurse, dirEntries, SpanMode, thisExePath, write, getcwd, remove;
import std.file: copy, getcwd;
import std.format: format;
import std.array: popFront, popBack, join, split, replace;
import std.process: execute, environment, executeShell, Config, spawnProcess, wait; 

import modules.files;
import modules.output;

int fileFindImports(string filename, string sourcePathAbsolute, string sourcePath) {
    FileEntry f = FileEntry(filename);
    string contents = readText(filename);
    auto modRegex = regex(r"^[^\S\r\n]*?module[^\S\r\n]+((?:\w+\.?)+)", "gm");
    auto impRegex = regex(r"^[^\S\r\n]*?import[^\S\r\n]+((?:\w+\.?)+)", "gm");

    auto mods = matchAll(contents, modRegex);
    foreach (mod; mods) {
        if (f.isModule == true) {
            writefln("Error: Found multiple module declarations in file \"%s\".", f.name);
            return 1;
        }
        f.isModule = true;
        f.moduleName = mod[1];
    }
    
    writelnVerbose(f.name.replace(sourcePathAbsolute, sourcePath).buildNormalizedPath);
    if (f.isModule) {
        writelnVerbose("    Module " ~ f.moduleName);
    } else {
        writelnVerbose("    Main Program ");
    }

    auto impt = matchAll(contents, impRegex);
    foreach (imp; impt) {
        if (imp[1].startsWith("System", "Externals", "std", "externals")) continue;
        f.imports ~= imp[1];
        writelnVerbose("    Import " ~ imp[1]);
    }
    // writeln(f.imports);

    if (f.isModule) {
        Files.modules ~= f;
    } else {
        Files.main ~= f;
    }
    writelnVerbose();

    // auto asyncRegex = regex(r"\bawait\b\s*?\((.*?)\)\s*?;", "gm");

    return 0;
}

int preprocessFile(FileEntry f, string tempFolder) {
    string[] imports = [];
    int cp = compileImports(f, imports);
    if (cp != 0) return cp;

    string newPath = tempFolder ~ dirSeparator ~ f.path.baseName;
    f.path.copy(newPath);

    auto mainRegex = regex(r"void\s+main\s*\(\s*\)", "gm");

    string mainCode = readText(newPath);

    auto mr = mainCode.matchAll(mainRegex);

    if (!mr.empty) {
        auto ff = new File(newPath, "w");
        ff.writeln("\ndocument.addEventListener(\"DOMContentLoaded\", main);");
        ff.close();
    }

    return 0;
}


// alias // alias\s+(\$?[\w\_]*)\s*\=\s*(.*?)\;
// import // import\s+((?:\w+\.?)+)\:((?:\s*(?:\w+)\s*\,?)+)\;
// import // ^[^\S\r\n]*?import[^\S\r\n]+(std\.?(?:\w+\.?)+)
// modules // module\s*((\w+\.?)+)\;
// main // void\s+main\s*\(\s*\)