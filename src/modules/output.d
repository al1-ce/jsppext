module modules.output;

import std.stdio: write, writeln;

static bool _verboseOutput = false;

void writeVerbose(T...)(T args) {
    if (_verboseOutput) write(args);
}

void writelnVerbose(T...)(T args) {
    if (_verboseOutput) writeln(args);
}