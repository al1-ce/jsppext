module modules.config;

import std.file: readText, exists, isFile, mkdirRecurse, dirEntries, SpanMode, thisExePath, write, getcwd, remove;
import std.path: buildNormalizedPath, absolutePath, isValidPath, dirSeparator, dirName, relativePath, baseName;
import std.stdio: writef, writefln, readln, stdin, stdout;
import std.stdio: writeln, write, File;
import std.array: popBack, split, array, replace;
import std.conv: to;
import std.datetime.systime: SysTime, Clock;
import std.algorithm: startsWith;

import core.stdc.stdlib: getenv;

import dyaml;

int configInit(string path) {
    string configPath = (path ~ dirSeparator ~ "jsppconf.yaml").buildNormalizedPath.absolutePath;
    if (configPath.exists) {
        writefln("The target directory already contains a \'jsppconf.yaml\' file. Aborting.");
        return 1;
    }
    string conf = "";

    string name = "";
    string description = "";
    string authors = "";
    string copyright = "";
    string license = "";

    string uname = getenv("USERNAME").to!string;
    
    promptField("name", "Name", "program", name);
    promptField("description", "Description", "Minimal JS++ application", description);
    string preferredName = promptFieldReturn("authors", "Author name", uname, authors);
    promptField("copyright", "Copyright string", 
        "Copyright (c) " ~ Clock.currTime.year.to!string ~ ", " ~ preferredName, copyright);
    promptField("license", "License", "MIT license", license);

    conf ~= name ~ "\n";
    conf ~= description ~ "\n";
    conf ~= authors ~ "\n";
    conf ~= copyright ~ "\n";
    conf ~= license ~ "\n";

    writef("Do you want to configure default build paths? (y/n): ");
    string configureBuild = readln();
    if (configureBuild.startsWith('y')) {
        string buildName = "";
        string sourcePath = "";
        string outputPath = "";

        string defaultBuild = promptFieldReturn("name", "Build name", "default", buildName);
        promptField("sourcePath", "Project source", "src/", sourcePath);
        promptField("outputPath", "Compiled output", "js/", outputPath);

        conf ~= "build:" ~ "\n";
        conf ~= "    " ~ defaultBuild ~ ": \n";
        conf ~= "        " ~ sourcePath ~ "\n";
        conf ~= "        " ~ outputPath ~ "\n";
        conf ~= "defaultBuild: " ~ defaultBuild ~ "\n";
    }

    auto file = File(configPath, "w");
    file.write(conf);
    file.close();

    writefln("Successfully created an empty project in \'" ~ path.absolutePath ~ "\'.");
    return 0;
}

void promptField(string name, string description, string _default, out string field) {
    writef("%s [%s]: ", description, _default);
    string line = readln();
    if (line == "\n") {
        field = name ~ ": " ~ _default;
    } else {
        line.popBack();
        field = name ~ ": " ~ line;
    }
}

string promptFieldReturn(string name, string description, string _default, out string field) {
    writef("%s [%s]: ", description, _default);
    string line = readln();
    if (line == "\n") {
        field = name ~ ": " ~ _default;
        return _default;
    } else {
        line.popBack();
        field = name ~ ": " ~ line;
        return line;
    }
}

string configGetGlobal(string configPath, string field) {
    Node root = Loader.fromFile(configPath).load();

    if (root.type != NodeType.mapping) return "";
    if (!root.containsKeyAs!string(field)) return "";

    return root[field].as!string;
}

string[] configGetBuilds(string configPath) {
    Node root = Loader.fromFile(configPath).load();

    if (root.type != NodeType.mapping) return [];
    if (!root.containsKeyType("build", NodeType.mapping)) return [];

    return cast(string[]) (root["build"].mappingKeys!string).array;
}

BuildSettings configGetBuildSettings(string configPath, string buildName) {
    Node root = Loader.fromFile(configPath).load();

    if (root.type != NodeType.mapping) return BuildSettings();
    if (!root.containsKeyType("build", NodeType.mapping)) return BuildSettings();
    if (!root["build"].containsKeyType(buildName, NodeType.mapping)) return BuildSettings();

    Node buildNode = root["build"][buildName];

    BuildSettings build = BuildSettings();

    build.isDefined = true;

    if (buildNode.containsKeyAs!string("sourcePath")) {
        build.sourcePath = buildNode["sourcePath"].as!string;
    }

    if (buildNode.containsKeyAs!string("outputPath")) {
        build.outputPath = buildNode["outputPath"].as!string;
    }

    if (buildNode.containsKeyAs!string("workingDirectory")) {
        build.workingDirectory = buildNode["workingDirectory"].as!string;
    }

    if (buildNode.containsKeyType("excludedSourceFiles", NodeType.sequence)) {
        build.excludedSourceFiles = cast(string[]) (buildNode["excludedSourceFiles"].sequence!string).array;
        for (int i = 0; i < build.excludedSourceFiles.length; i++) {
            build.excludedSourceFiles[i] = build.excludedSourceFiles[i].buildNormalizedPath.absolutePath;
        }
    }

    if (buildNode.containsKeyType("excludedDirectories", NodeType.sequence)) {
        build.excludedDirectories = cast(string[]) (buildNode["excludedDirectories"].sequence!string).array;
        for (int i = 0; i < build.excludedDirectories.length; i++) {
            build.excludedDirectories[i] = build.excludedDirectories[i].buildNormalizedPath.absolutePath;
        }
    }

    if (buildNode.containsKeyType("supressedWarnings", NodeType.sequence)) {
        build.supressedWarnings = cast(string[]) (buildNode["supressedWarnings"].sequence!string).array;
    }

    if (buildNode.containsKeyType("disabledSyntaxChanges", NodeType.sequence)) {
        build.disabledSyntaxChanges = cast(string[]) (buildNode["disabledSyntaxChanges"].sequence!string).array;
    }

    if (buildNode.containsKeyAs!bool("nolint")) {
        build.noLint = buildNode["nolint"].as!bool;
    }

    if (buildNode.containsKeyAs!bool("verbose")) {
        build.verbose = buildNode["verbose"].as!bool;
    }

    if (buildNode.containsKeyAs!bool("debug")) {
        build.isDebug = buildNode["debug"].as!bool;
    }

    if (buildNode.containsKeyAs!bool("preprocess")) {
        build.preprocess = buildNode["preprocess"].as!bool;
    }

    if (buildNode.containsKeyAs!bool("async")) {
        build.async = buildNode["async"].as!bool;
    }

    if (buildNode.containsKeyAs!bool("enableFloat")) {
        if (!buildNode["enableFloat"].as!bool) {
            build.disabledSyntaxChanges ~= "float";
        }
    }

    return build;
}

private bool containsKeyType(Node node, string key, NodeType type) {
    if (node.containsKey(key)) {
        if (node[key].type == type) {
            return true;
        }
    }
    return false;
}

private bool containsKeyAs(T)(Node node, string key) {
    if (node.containsKey(key)) {
        if (node[key].convertsTo!T) {
            return true;
        }
    }
    return false;
}

struct BuildSettings {
    string sourcePath = "src/";
    string outputPath = "js/";
    string workingDirectory = ".";
    string[] excludedSourceFiles = [];
    string[] excludedDirectories = [];
    string[] supressedWarnings = [];
    string[] disabledSyntaxChanges = [];
    bool noLint = false;
    bool verbose = false;
    bool isDebug = false;
    bool preprocess = true;
    bool async = false;
    bool isDefined = false;
}
