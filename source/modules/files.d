module modules.files;

import std.regex;
import std.algorithm.searching: endsWith;
import std.stdio: writefln;

static class Files {
    public static FileEntry[] main;
    public static FileEntry[] modules;
}

struct FileEntry {
    string name;
    bool isModule;
    string[] imports;
    string moduleName;
    bool isProcessed;
    string originalPath;

    alias path = name;

    this(string _name) {
        name = _name;
        originalPath = _name;
        isModule = false;
        imports = [];
        moduleName = "";
        isProcessed = false;
    }
}

bool isPathFile(string path) {
    auto re = regex(r"^.*?\.(?:\w+)$");
    auto cap = path.matchFirst(re);
    return !cap.empty();
}

string findFilePath(string file, FileEntry[] files) {
    for (int i = 0; i < files.length; i ++) {
        FileEntry e = files[i];
        if (e.name.endsWith(file)) {
            return e.name;
        }
    }
    return file;
}

string findFilePath(string file, FileEntry[] files1, FileEntry[] files2) {
    string _out = findFilePath(file, files1);
    if (_out == file) {
        return findFilePath(file, files2);
    }
    return _out;
}

int findModuleIndex(FileEntry[] entries, string moduleName) {
    int i = 0;
    foreach (FileEntry e; entries) {
        if (e.moduleName == moduleName) {
            return i;
        }
        i++;
    }

    return -1;
}

int compileImports(FileEntry file, ref string[] imports) {
    // writef("     : "); writeln(imports);
    // writef(file.name ~ " : "); writeln(file.imports);
    for (int i = 0; i < file.imports.length; i++) {
        string imp = file.imports[i];
        int idx = Files.modules.findModuleIndex(imp);
        if (idx == -1) {
            writefln("Error: Can't find module \"%s\".", imp);
            return 1;
        }
        if (imports.canFindString(Files.modules[idx].name)) continue;
        imports ~= Files.modules[idx].name;
        int cp = compileImports(Files.modules[idx], imports);
        if (cp != 0) return cp;
    }
    return 0;
}

bool canFindString(string[] arr, string val) {
    for (int i = 0; i < arr.length; i ++) {
        if (arr[i] == val) return true;
    }
    return false;
}