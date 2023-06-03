module modules.files;

import std.regex;
import std.algorithm.searching: endsWith, canFind;
import std.stdio: writefln;
import std.path: buildNormalizedPath, absolutePath;
import modules.preprocess: AsyncStorage;
import modules.output: writelnVerbose;

static class Files {
    public static FileEntry[] main;
    public static FileEntry[] modules;

    public static void replacePath(string originalPath, string newPath) {
        for (int i = 0; i < main.length; i ++) {
            if (main[i].originalPath == originalPath) {
                main[i].name = newPath;
                return;
            }
        }
        for (int i = 0; i < modules.length; i ++) {
            if (modules[i].originalPath == originalPath) {
                modules[i].name = newPath;
                return;
            }
        }
    }

    public static void addStorage(string originalPath, AsyncStorage s) {
        for (int i = 0; i < main.length; i ++) {
            if (main[i].originalPath == originalPath) {
                main[i].asyncStorage.add(s);
                return;
            }
        }
        for (int i = 0; i < modules.length; i ++) {
            if (modules[i].originalPath == originalPath) {
                modules[i].asyncStorage.add(s);
                return;
            }
        }
    }

    public static FileEntry getFile(string originalPath) {
        for (int i = 0; i < main.length; i ++) {
            if (main[i].originalPath == originalPath) {
                return main[i];
            }
        }
        for (int i = 0; i < modules.length; i ++) {
            if (modules[i].originalPath == originalPath) {
                return modules[i];
            }
        }
        writefln("Unable to find file with path \"%s\".", originalPath);
        assert(0);
    }

    public static FileEntry findModule(string moduleName) {
        for (int i = 0; i < modules.length; i ++) {
            if (modules[i].moduleName == moduleName) {
                return modules[i];
            }
        }
        writefln("Unable to find module name \"%s\".", moduleName);
        assert(0);
    }

    public static string findModuleName(string modulePath) {
        for (int i = 0; i < modules.length; i ++) {
            // writefln("%s, %s", modules[i].originalPath.fixpath, modulePath.fixpath);
            if (modules[i].originalPath.fixpath == modulePath.fixpath) {
                return modules[i].moduleName;
            }
        }
        writefln("Unable to find module at \"%s\".", modulePath);
        assert(0);
    }

    public static string[] getModuleNameList(FileEntry f, string[] scannedPaths = []) {
        writelnVerbose("Getting module name list for %s", f.originalPath);
        string[] moduleList = [];
        if (scannedPaths.canFind(f.originalPath)) return moduleList;
        scannedPaths ~= f.originalPath;
        for (int i = 0; i < f.imports.length; i ++) {
            string name = f.imports[i];
            // string path = f.imports[i];
            // string name = Files.findModuleName(path);
            moduleList ~= name;
            moduleList ~= getModuleNameList(Files.findModule(name), scannedPaths);
        }
        // import std.stdio; writeln(moduleList.noDupes);
        return moduleList.noDupes;
    }
}

string fixpath(string path) {
    return path.buildNormalizedPath.absolutePath;
}

T[] noDupes(T)(in T[] s) {
     import std.algorithm: canFind;
     T[] result;
     foreach (T c; s)
         if (!result.canFind(c))
             result ~= c;
     return result;
}

struct FileEntry {
    string name;
    bool isModule;
    string[] imports;
    string moduleName;
    bool isProcessed;
    string originalPath;

    AsyncStorage asyncStorage;

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
            return e.originalPath;
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