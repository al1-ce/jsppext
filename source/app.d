import std.stdio: writef, writefln, readln, stdin, stdout;
import std.getopt: getopt, GetoptResult, config;
import std.array: popFront, popBack, join, split, replace;
import std.file: readText, exists, isFile, mkdirRecurse, dirEntries, rmdirRecurse;
import std.file: SpanMode, thisExePath, write, getcwd, remove, rmdir, mkdir;
import std.path: buildNormalizedPath, absolutePath, isValidPath, dirSeparator, dirName, relativePath;
import std.process: execute, environment, executeShell, Config, spawnProcess, wait;
import std.conv: to;
import std.regex;
import std.algorithm.searching: startsWith, endsWith, canFind;

import std.stdio: writeln, write, File;

import sily.getopt;

import modules.config;
import modules.files;
import modules.compiler;
import modules.output;

const string jsppextVersion = "1.0.5";

void cleanup() {
    string tempFolder = getcwd ~ dirSeparator ~ "____jspp_temp";
    string compileLog = tempFolder ~ dirSeparator ~ "____jspp_compilelog";
    string versionLog = tempFolder ~ dirSeparator ~ "____jspp_versionlog";
    if (tempFolder.exists) tempFolder.rmdirRecurse();
    if (compileLog.exists) compileLog.remove();
    if (versionLog.exists) versionLog.remove();
}

int main(string[] args) {
    cleanup();
    string _usage = "jsppext [options] [file]\n";

    bool _verbose = false;
    bool _debug = false;
    bool _execute = false;
    string _targetPath = "";
    bool _version = false;
    bool _extversion = false;
    bool _nolint = false;
    bool _preprocess = false;
    bool _initConf = false;
    bool _buildConf = false;
    bool _runConf = false;

    GetoptResult helpInfo = getopt(
        args, 
        config.passThrough,
        "debug|d", "Comile in debug mode", &_debug,
        "execute|e", "Execute input JS++ program", &_execute,
        "nolint|n", "Removes error transcription (outputs js++ out instead of jsppext).", &_nolint,
        "output|o", "Output target", &_targetPath,
        "unprocessed|u", "Disables pre/post-processing of files (custom syntax)", &_preprocess,
        "verbose|v", "Produces verbose output", &_verbose,
        "init|i", "Initialises project", &_initConf,
        "build|b", "Builds using \"jsppconf.yaml\" configuration", &_buildConf,
        "run|r", "Builds & runs using \"jsppconf.yaml\" configuration", &_runConf,
        "version", "Display the JS++ compiler version and exit", &_version,
        "extver", "Display the jsppext version and exit", &_extversion,
    );

    _preprocess = !_preprocess;

    if (helpInfo.helpWanted) {
        Commands[] com = [];
        printGetopt("", _usage, com, helpInfo.options);
        return 0;
    }

    string jsppPath = thisExePath().dirName() ~ dirSeparator ~ "js++";
    version (Windows) jsppPath ~= ".exe";

    if (_version) {
        wait(spawnProcess([jsppPath, "--version"]));
        return 0;
    }

    if (_extversion) {
        writefln("jsppext v." ~ jsppextVersion);
        return 0;
    }

    _verboseOutput = _verbose;

    string[] nargs = args.dup;
    
    string configPath = (getcwd ~ dirSeparator ~ "jsppconf.yaml").buildNormalizedPath.absolutePath;
    if (_buildConf || _runConf) {
        /* -------------------------- Auto build via config ------------------------- */
        if (!configPath.exists) {
            writefln(
                "No project config (jsppconf.yaml) was found in\n%s\n" ~ 
                "Please run jsppext from the root directory of existing project, or run\n" ~ 
                "\"jsppext --init\" to create new package.\n\nNo valid root package found. Aborting.", 
                getcwd);
            return 1;
        }

        BuildSettings buildSettings;
        string buildName;
        if (nargs.length == 1) {
            buildName = configGetGlobal(configPath, "defaultBuild");
            if (buildName != "") {
                buildSettings = configGetBuildSettings(configPath, buildName);
            }
        } else {
            buildName = nargs[1];
            buildSettings = configGetBuildSettings(configPath, buildName);
        }

        if (buildSettings.isDefined) {
            writefln("Using \"%s\" build configuration.", buildName);
        } else {
            writefln("Using default build configuration.");
        }

        string requiredExtVersion = configGetGlobal(configPath, "extensionVersion");
        string requiredCmpVersion = configGetGlobal(configPath, "compilerVersion");

        if (requiredExtVersion != jsppextVersion && requiredExtVersion != "") {
            writefln(
                "Error: Incompatable jsppext version (%s). Config requires \"%s\" version.", 
                jsppextVersion, requiredExtVersion);
            return 1;
        }

        string tempFolder = getcwd ~ dirSeparator ~ "____jspp_temp";
        mkdir(tempFolder);

        string coutPath = tempFolder ~ dirSeparator ~ "____jspp_versionlog";
        auto processOut = File(coutPath, "w+");

        wait(spawnProcess([jsppPath, "--version"], stdin, processOut));
        processOut.close();
        auto cout = File(coutPath, "r");
        string cmpVersion = cout.readln().replace("JS++(R) v.", "").replace("\n", "");
        cout.close();

        if (requiredCmpVersion != cmpVersion && requiredCmpVersion != "") {
            writefln(
                "Error: Incompatable js++ version (%s). Config requires \"%s\" version.", 
                cmpVersion, requiredCmpVersion);
            if (!buildSettings.isDebug) cleanup();
            return 1;
        }

        _verboseOutput = buildSettings.verbose || _verbose;

        int ret = compile(CompileSettings(
            buildSettings.sourcePath,
            buildSettings.sourcePath.buildNormalizedPath.absolutePath,
            buildSettings.sourcePath,
            buildSettings.sourcePath.buildNormalizedPath.absolutePath,
            buildSettings.outputPath,
            buildSettings.excludedSourceFiles, 
            buildSettings.excludedDirectories ~ ["____jspp_temp"],
            buildSettings.supressedWarnings,
            buildSettings.isDebug, _runConf, 
            buildSettings.noLint, buildSettings.preprocess
        ));
        if (!buildSettings.isDebug) cleanup();
        return ret;

    } else {
        /* ---------------------- Manual build via command line --------------------- */
        string sourcePath = "";
        if (nargs.length == 1) {
            sourcePath = ".";
        } else {
            sourcePath = nargs[1].buildNormalizedPath;
        }

        string sourcePathAbsolute = sourcePath.buildNormalizedPath.absolutePath; 

        if (_targetPath == "") _targetPath = ".";

        if (!sourcePath.exists()) {
            writefln("Error: Path \"%s\" is not valid.", sourcePath);
            return 1;
        }
    
        if (_initConf) {
            return configInit(getcwd);
        }

        if (nargs.length > 2) {
            writeln("Warning: Cannot set more then one file or directory to compile, other files are omitted.");
        }

        string tempFolder = getcwd ~ dirSeparator ~ "____jspp_temp";
        mkdir(tempFolder);
        int ret = compile(CompileSettings(
            sourcePath, sourcePathAbsolute, 
            sourcePath.isFile ? sourcePath.dirName : sourcePath, 
            sourcePath.isFile ? sourcePathAbsolute.dirName : sourcePathAbsolute, 
            _targetPath, 
            [], ["____jspp_temp"], [],
            _debug, _execute, _nolint, _preprocess
        ));
        if (!_debug) cleanup();
        return ret;
    }
}