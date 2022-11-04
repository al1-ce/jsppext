module modules.compiler;

import std.conv: to;
import std.regex;
import std.algorithm.searching: startsWith, endsWith, canFind;
import std.stdio: writef, writefln, readln, stdin, stdout;
import std.stdio: writeln, write, File;
import std.path: buildNormalizedPath, absolutePath, isValidPath, dirSeparator, dirName, relativePath, baseName;
import std.file: readText, exists, isFile, mkdirRecurse, dirEntries, SpanMode, thisExePath, write, getcwd, remove;
import std.format: format;
import std.array: popFront, popBack, join, split, replace;
import std.process: execute, environment, executeShell, Config, spawnProcess, wait; 

import modules.files;
import modules.output;
import modules.compileerror;
import modules.preprocess;

int compile(CompileSettings s) {
    if (!s.sourcePath.exists()) {
        writefln("Error: Path \"%s\" is not valid.", s.sourcePath);
        return 1;
    }

    if (!s.targetPath.isValidPath()) {
        writefln("Error: Path \"%s\" is not valid.", s.targetPath);
        return 1;
    }

    if (!s.sourcePath.isFile && s.targetPath.isPathFile()) {
        writefln("Error: Cannot output directory into file. Please specify directory for --output, not file.");
        return 1;
    }

    auto entries = dirEntries(s.scanPathAbsolute, "*.{jspp,jpp,js++}", SpanMode.depth);

    writelnVerbose("Compiling program lists & module lists\n");
    
    foreach (file; entries) {
        if (file.name.absolutePath.isExcluded(s.excludedSourceFiles, s.excludedDirectories)) continue;
        int cp = fileFindImports(file.name, s.scanPathAbsolute, s.scanPath);
        if (cp != 0) return cp;
    }

    writelnVerbose("\nCompiling programs import lists\n");

    /* --------------------------- Preprocessing files -------------------------- */
    if (s.preprocess) {
        foreach (FileEntry f; Files.main) {
            if (s.sourcePath.isFile && f.name != s.sourcePathAbsolute) continue;
            string fileName = f.name.replace(s.scanPathAbsolute, s.scanPath).buildNormalizedPath;

            writelnVerbose("Prepocessing \"%s\"\n".format(fileName));
            string tempFolder = getcwd ~ dirSeparator ~ "____jspp_temp";
            preprocessFile(f, tempFolder, s.scanPathAbsolute);
        }

        foreach (FileEntry f; Files.modules) {
            if (s.sourcePath.isFile && f.name != s.sourcePathAbsolute) continue;
            string fileName = f.name.replace(s.scanPathAbsolute, s.scanPath).buildNormalizedPath;

            writelnVerbose("Prepocessing \"%s\"\n".format(fileName));
            string tempFolder = getcwd ~ dirSeparator ~ "____jspp_temp";
            preprocessFile(f, tempFolder, s.scanPathAbsolute);
        }
    }

    /* -------------------------- Compiling main files -------------------------- */
    foreach (FileEntry f; Files.main) {
        if (s.sourcePath.isFile && f.name != s.sourcePathAbsolute) continue;
        string fileName = f.name.replace(s.scanPathAbsolute, s.scanPath).buildNormalizedPath;
        writelnVerbose(fileName);

        // TODO make more dependant on id
        int cmp = compileFile(Files.getFile(f.originalPath), s);
        if (cmp != 0) return cmp;
    }

    return 0;
}

int compileFile(FileEntry f, CompileSettings s) {
    string[] imports = [];
    int cp = compileImports(f, imports);
    if (cp != 0) return cp;

    if (imports.length > 0) {
        writelnVerbose("    Imports: ");
    } else {
        writelnVerbose("    No imports");
    }

    string[] _args = [f.name.replace(s.scanPathAbsolute, s.scanPath).buildNormalizedPath];

    for (int i = 0; i < imports.length; i++) {
        string imprt = imports[i];
        _args ~= imprt.replace(s.scanPathAbsolute, s.scanPath).buildNormalizedPath;
        writelnVerbose("    " ~ imprt.replace(s.scanPathAbsolute, s.scanPath).buildNormalizedPath);
    }

    bool _doOutput = true;

    if (s.debugBuild) _args ~= "-d";
    if (s.doExecute) {
        if (s.sourcePath.isFile) {
            _args ~= "-e";
            _doOutput = false;
        } else {
            writeln("Warning: Directory auto doesn't work with execute.");
        }
    }

    if (_doOutput) {
        _args ~= "-o";
        
        if (!s.targetPath.buildNormalizedPath.isPathFile()) {
            auto re = regex(r"(?<=\.)(?:jpp|jspp|js\+\+)$");

            _args ~= f.originalPath.replace(s.scanPathAbsolute, s.targetPath).buildNormalizedPath.replaceAll(re, "js");

            string outPath = f.originalPath.replace(s.scanPathAbsolute, s.targetPath).buildNormalizedPath.dirName();

            if (!outPath.exists) {
                mkdirRecurse(outPath);
            }
        } else {
            auto re = regex(r"(?<=\.)(?:jpp|jspp|js\+\+)$");
            string newPath = s.targetPath.buildNormalizedPath.replaceAll(re, "js");
            _args ~= newPath;

            string outDir = newPath.dirName();

            if (!outDir.exists) {
                mkdirRecurse(outDir);
            }

        }
    }

    /* ------------------------- Executing jspp compiler ------------------------ */

    writelnVerbose();
    writelnVerbose("Command for \"" ~ 
        f.originalPath.replace(s.scanPathAbsolute, s.scanPath).buildNormalizedPath ~ "\":");
    writelnVerbose((["js++"] ~ _args).join(" "));
    writelnVerbose();

    writelnVerbose("\n===== %s =====\n"
        .format(f.originalPath.replace(s.scanPathAbsolute, s.scanPath).buildNormalizedPath));

    string jsppPath = thisExePath().dirName() ~ dirSeparator ~ "js++";
    version (Windows) jsppPath ~= ".exe";

    if (s.noLint) {
        auto pidErr = wait(spawnProcess([jsppPath] ~ _args, stdin, stdout));

        if (pidErr == 139 || pidErr == -1_073_741_819) {
            string filep = f.originalPath.replace(s.scanPathAbsolute, s.scanPath).buildNormalizedPath;
            printError( filep, 0, 0, "JSPPE0000", "Segmentation fault" );
            return 139;
        }
    } else {
        string tempFolder = getcwd ~ dirSeparator ~ "____jspp_temp";
        string coutPath = tempFolder ~ dirSeparator ~ "____jspp_compilelog";
        auto processOut = File(coutPath, "w+");

        auto pidErr = wait(spawnProcess([jsppPath] ~ _args, stdin, processOut));
        processOut.close();

        if (pidErr == 139 || pidErr == -1_073_741_819) {
            string filep = f.originalPath.replace(s.scanPathAbsolute, s.scanPath).buildNormalizedPath;
            printError( filep, 0, 0, "JSPPE0000", "Segmentation fault" );
            return 139;
        }

        auto cout = File(coutPath, "r");
        string line;

        while ((line = cout.readln()) !is null) {
            checkCompilerError(line, s);
        }
        cout.close();
    }

    return 0;
}

bool isExcluded(string absolutePath, string[] excludedFiles, string[] excludedDirectories) {
    if (excludedFiles.canFind(absolutePath)) return true;
    foreach (dir; excludedDirectories) {
        if (absolutePath.startsWith(dir)) return true;
    }
    return false;
}

struct CompileSettings {
    string sourcePath = "src/";
    string sourcePathAbsolute = "src/";
    string scanPath = "src/";
    string scanPathAbsolute = "src/";
    string targetPath = "js/";
    string[] excludedSourceFiles = [];
    string[] excludedDirectories = [];
    string[] supressedWarnings = [];
    bool debugBuild = false;
    bool doExecute = false;
    bool noLint = false;
    bool preprocess = true;
}