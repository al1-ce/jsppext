module modules.preprocess;

import std.conv: to;
import std.regex;
import std.algorithm.searching: startsWith, endsWith, canFind;
import std.stdio: writef, writefln, readln, stdin, stdout;
import std.stdio: writeln, File;
import std.path: buildNormalizedPath, absolutePath, isValidPath, dirSeparator, dirName, relativePath, baseName;
import std.file: readText, exists, isFile, mkdirRecurse, dirEntries, SpanMode, thisExePath, write, getcwd, remove;
import std.file: copy, getcwd, write;
import std.format: format;
import std.array: popFront, popBack, join, split, replace;
import std.process: execute, environment, executeShell, Config, spawnProcess, wait; 
import std.uni: toLower;
import std.string: capitalize, indexOf;

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

int preprocessFile(FileEntry f, string tempFolder, string srcFolder, 
    string[] disabledSyntaxChanges = []) {
    // string[] imports = [];
    // int cp = compileImports(f, imports);
    // if (cp != 0) return cp;

    string newPath = tempFolder ~ dirSeparator ~ f.path.relativePath(srcFolder.buildNormalizedPath.absolutePath);
    if (!newPath.dirName.exists) mkdirRecurse(newPath.dirName);
    f.path.copy(newPath);

    bool mainEnabled = !disabledSyntaxChanges.canFind("main");
    bool aliasEnabled = !disabledSyntaxChanges.canFind("alias");
    bool stringEnabled = !disabledSyntaxChanges.canFind("string");
    bool importEnabled = !disabledSyntaxChanges.canFind("import");
    bool moduleEnabled = !disabledSyntaxChanges.canFind("module");
    bool structEnabled = !disabledSyntaxChanges.canFind("struct");
    bool constEnabled = !disabledSyntaxChanges.canFind("const");

    string mainCode = readText(newPath);

    if (mainEnabled) {
        auto mainRegex = regex(r"void\s+main\s*\(\s*\)", "gm");
        auto externalRegex = regex(r"external\s*document\s*\;", "gm");
        auto importRegex = regex(r"import\s*(?:externals\.dom|Externals\.DOM)\s*\;", "gm");

        auto mr = mainCode.matchAll(mainRegex);

        if (!mr.empty) {
            writelnVerbose("Found \"void main(){}\", injecting main autoexec.");
            // auto ff = new File(newPath, "w");
            if (mainCode.matchAll(externalRegex).empty && mainCode.matchAll(importRegex).empty) {
                mainCode = "external document;" ~ mainCode;
                writelnVerbose("Missing \"external document;\", injecting.");
            }
            mainCode = mainCode ~ "\ndocument.addEventListener(\"DOMContentLoaded\", main);";
            // ff.write(mainCode);
            // ff.close();
        }
    }

    if (aliasEnabled) {
        auto aliasRegex = regex(r"(?:(\w+)\s+)?alias\s+(\$?(?:\w|\_)+)\s*\=\s*(.*?)\;", "gm");
        auto aliases = matchAll(mainCode, aliasRegex);
        mainCode = mainCode.replaceAll(aliasRegex, "");
        // TODO scopes
        foreach (match; aliases) {
            string aName = match[2];
            string aCode = match[3];
            auto partRegex = regex(r"\b" ~ aName ~ r"\b");
            mainCode = mainCode.replaceAll(partRegex, aCode);
        }
    }

    if (stringEnabled) {
        auto tickRegex = regex(r"(?<!\\)\`((?:.*?[\n\r]?(?:\\\`)?)*?)\`", "gm");
        auto charRegex = regex(r"(?<!\\)\'((?:.*?(?:\\\')?)*?)\'", "gm");

        mainCode = mainCode.replaceAll(tickRegex, "\"\"\"$1\"\"\"");
        mainCode = mainCode.replaceAll(charRegex, "`$1`");
    }

    if (importEnabled) {
        auto importRegex = regex(r"import\s+((?:\w+\.?)+)(?:\:\s*((?:(?:\w+)\s*(?:\,\s*)?)+))?\;", "gm");
        auto matches = mainCode.matchAll(importRegex);
        // TODO scopes
        foreach (match; matches) {
            string imp = match[1];
            if (!(imp.startsWith("std") || imp.startsWith("externals")) ) continue;
            string[] mods = imp.split(".");
            string[] exceptions = ["DOM", "URI"];
            bool isException = false;
            for (int i = 0; i < mods.length; i++) {
                if (isException) isException = false;
                if (mods[i] == "std") {
                    mods[i] = "System";
                    continue;
                }
                for (int j = 0; j < exceptions.length; j++) {
                    if (mods[i] == exceptions[j].toLower) {
                        mods[i] = exceptions[j];
                        isException = true;
                        break;
                    }
                }
                if (!isException) {
                    mods[i] = mods[i].capitalize;
                }
            }
            
            mainCode = mainCode.replace(match[0], "import " ~ mods.join(".") ~ ";");
        }
    }

    // this might be a bit slow becuase of indexOf repeatedly
    if (moduleEnabled && f.isModule) {
        auto moduleRegex = regex(r"module\s*((?:\w+\.?)+)\;", "gm");
        auto importRegex = regex(r"import\s+.*?\;", "gm");
        auto externalRegex = regex(r"external\s+.*?\;", "gm");
        auto importMatches = mainCode.matchAll(importRegex);
        auto externalMatches = mainCode.matchAll(externalRegex);
        string lastMatch = "";
        int lastPos = 0;
        foreach (match; importMatches) {
            int pos = mainCode.indexOf(match[0]).to!int;
            if (pos > lastPos) {
                lastPos = pos;
                lastMatch = match[0];
            }
        }
        foreach (match; externalMatches) {
            int pos = mainCode.indexOf(match[0]).to!int;
            if (pos > lastPos) {
                lastPos = pos;
                lastMatch = match[0];
            }
        }
        // TODO might not work with trailing /*
        auto mname = mainCode.matchFirst(moduleRegex);
        if (!mname.empty) {
            writelnVerbose("Found module name \"%s\". Converting.".format(mname[1]));
            mainCode = mainCode.replaceFirst(moduleRegex, "");
            if (lastMatch == "") {
                mainCode = "module " ~ mname[1] ~ " { " ~ mainCode ~ " \n} ";
            } else {
                mainCode = mainCode.replace(lastMatch, lastMatch ~ "module " ~ mname[1] ~ " { ");
                mainCode ~= " \n} ";
            }
        }
    }

    if (structEnabled) {
        auto structRegex = regex(r"\bstruct\b", "gm");
        mainCode = mainCode.replaceAll(structRegex, "class");
    }

    if (constEnabled) {
        auto constRegex = regex(r"\bconst\b", "gm");
        mainCode = mainCode.replaceAll(constRegex, "final");
    }

    write(newPath, mainCode);

    Files.replacePath(f.originalPath, newPath);

    return 0;
}


// alias // alias\s+(\$?[\w\_]*)\s*\=\s*(.*?)\;
// import // import\s+((?:\w+\.?)+)\:((?:\s*(?:\w+)\s*\,?)+)\;
// modules // module\s*((?:\w+\.?)+)\;
// main // void\s+main\s*\(\s*\)