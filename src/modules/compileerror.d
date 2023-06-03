module modules.compileerror;

import std.conv: to;
import std.regex;
import std.algorithm.searching: startsWith, endsWith, canFind;
import std.stdio: writef, writefln, readln, stdin, stdout;
import std.stdio: writeln, write, File;
import std.path: buildNormalizedPath, absolutePath, isValidPath, dirSeparator, dirName, relativePath, baseName;
import std.file: readText, exists, isFile, mkdirRecurse, dirEntries, SpanMode, thisExePath, write, getcwd, remove;

import modules.files;
import modules.compiler: CompileSettings;

private const auto errRegex = 
    regex(r"(?:\[  ERROR  \] )(.*?)(?:\: )(.*?)(?: at line )(\d+?)(?: char )(\d+?)(?: at )(.*?)\s");
private const auto warnRegex = 
    regex(r"(?:\[ WARNING \] )(.*?)(?:\: )(.*?)(?: at line )(\d+?)(?: char )(\d+?)(?: at )(.*?)\s");
private const auto continueRegex = regex(r"(.*?)(?: at line )(\d+?)(?: char )(\d+?)(?: at )(.*?)\s");
private const auto warnContRegex = regex(r"(.*?)(?: at line )(\d+?)(?: char )(\d+?)(?: at )(.*?)\s");
private const auto parseRegex = regex(r"Parse Error: Line (\d*?)\: (.*) \((.*)\)");

private CompileError err;

private bool isErrPrev = false;
private bool isWarPrev = false;

void checkCompilerError(string line, CompileSettings s) {
    auto capErr = line.matchFirst(errRegex);
    auto carErrCon = line.matchFirst(continueRegex);
    auto capWar = line.matchFirst(warnRegex);
    auto capWarCon = line.matchFirst(warnContRegex);
    auto capParse = line.matchFirst(parseRegex);

    if (!capErr.empty()) {
        isErrPrev = true; isWarPrev = false;
        err = CompileError(
            capErr[1], 
            ("0" ~ capErr[3]).to!int, 
            ("0" ~ capErr[4]).to!int + 2, 
            capErr[2], capErr[5]);

        string errfile = findFilePath(err.file, Files.main, Files.modules);

        err.file = errfile.buildNormalizedPath.relativePath(getcwd());

        printError(  err.file, err.line, err.pos, err.code, err.message );
        // source\app.d(190,34): Error: undefined identifier `caap`, did you mean variable `cap`?
    } else 
    if (!carErrCon.empty() && isErrPrev) {
        err = CompileError(
            err.code, 
            ("0" ~ carErrCon[2]).to!int, 
            ("0" ~ carErrCon[3]).to!int + 2, 
            err.message, 
            carErrCon[4]
            );

        string errfile = findFilePath(err.file, Files.main, Files.modules);

        err.file = errfile.buildNormalizedPath.relativePath(getcwd());

        printError(  err.file, err.line, err.pos, err.code, err.message );
    } else 
    if (!capWar.empty()) {
        isWarPrev = true; isErrPrev = false;
        if (s.supressedWarnings.canFind(capWar[1])) {
            err.code = capWar[1];
            return;
        }
        err = CompileError(
            capWar[1], 
            ("0" ~ capWar[3]).to!int, 
            ("0" ~ capWar[4]).to!int + 2, 
            capWar[2], capWar[5]);

        string errfile = findFilePath(err.file, Files.main, Files.modules);

        err.file = errfile.buildNormalizedPath.relativePath(getcwd());

        printWarning( err.file, err.line, err.pos, err.code, err.message );
        // test\src\main.jpp(7,2): Error[JSPPE5040]: `Test' cannot be used here, type is expected.
    } else 
    if (!capWarCon.empty() && isWarPrev) {
        if (s.supressedWarnings.canFind(err.code)) {
            return;
        }
        err = CompileError(
            err.code, 
            ("0" ~ capWarCon[2]).to!int, 
            ("0" ~ capWarCon[3]).to!int + 2, 
            err.message, 
            capWarCon[4]
            );

        string errfile = findFilePath(err.file, Files.main, Files.modules);

        err.file = errfile.buildNormalizedPath.relativePath(getcwd());

        printWarning( err.file, err.line, err.pos, err.code, err.message );
    } else
    if (!capParse.empty()) {
        isWarPrev = false; isErrPrev = false;
        err = CompileError("JSPPE0000", ("0" ~ capParse[1]).to!int, 0, capParse[2], capParse[3]);

        string errfile = findFilePath(err.file, Files.main, Files.modules);

        err.file = errfile.buildNormalizedPath.relativePath(getcwd());

        printError( err.file, err.line, err.pos, err.code, err.message );
    } else {
        write(line);
    }
}

/** 
 * 
 * Params:
 *   file = Relative filepath
 *   line = Error line
 *   pos = Error pos on line
 *   code = Error code
 *   message = Error message
 */
void printError(string file, int line, int pos, string code, string message) {
    printProblem( file, line, pos, "Error", code, message );
}

/** 
 * 
 * Params:
 *   file = Relative filepath
 *   line = Error line
 *   pos = Error pos on line
 *   code = Error code
 *   message = Error message
 */
void printWarning(string file, int line, int pos, string code, string message) {
    printProblem( file, line, pos, "Warning", code, message );
}

/** 
 * 
 * Params:
 *   file = Relative filepath
 *   line = Error line
 *   pos = Error pos on line
 *   severity = Error severity (Warning, Error)
 *   code = Error code
 *   message = Error message
 */
void printProblem(string file, int line, int pos, string severity, string code, string message) {
    writefln( "%s(%d,%d): %s[%s]: %s.", file, line, pos, severity, code, message );
}

struct CompileError {
    string code;
    int line;
    int pos;
    string message;
    string file;
}