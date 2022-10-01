# Extension to js++ compiler

## Installation:

Copy `jsppext` into your js++ compiler location (directory with `js++` executable)

## Building:

### Prerequisites:

[D language](https://dlang.org) compiler is required. 

Clone repository and run `dub build -b release`. Dub is going to compile `jsppext` into
`bin` folder.

## Usage: 
All options for compiler (v.0.10.0) are fully translated and used in same way as js++ options with exception of `-o`.

Updated option `-o, --output` now compiles all main files in directory specified in source 
into directory specified after this option.

## Stdout:
Also `jsppext` changes compile output to be more readable for any linters. \
Old format: [  ERROR  ] `ErrorCode`: `ErrorMessage` at line `Line` char `Pos` at `FileName` \
New format: `FilePath`(`Line`,`Pos`): Error[`ErrorCode`]: `ErrorMessage`. 

Mainly it addresses `FileName` part in original output. `jsppext` tries to predict filepath from error based on constructed file list for compilation. \
Important part is: this way of deducting filepath have a flaw in which if several files with 
same name have error only one will be picked (by path alphabetically).

### !IMPORTANT!
- If `--output` option is omitted then it defaults to `.` path.
- `jsppext --output` scans only for files with extensions `jspp`, `js++` and `jpp`.
- If source specified as filepath you can set output filepath. I.e. `jsppext src/main.jpp -o js/out.js`, else it's going to only change filename (`jsppext src/main.jpp -o js/` -> `js/main.js`).
- You cannot specify several files to compile, except if you specify directory. For that, please, use original compiler.

### Example
Your source tree is:
```
src/
 ├─ main1.jpp
 ├─ main2.jpp
 ├─ main3.jpp
 ├─ notmain.js
 ├─ mainmod/
 │  └─ main4.jpp
 ├─ modules/
 │  ├─ innermodule1.jpp
 │  ├─ innermodule2.jpp
 │  └─ list/
 │     ├─ listmodule1.jpp
 │     └─ listmodule2.jpp
 └─ outermodule.jpp
```

`jsppext src/ -o js/` going to compile it into:

```
js/
 ├─ main1.js
 ├─ main2.js
 ├─ main3.js
 └─ mainmod/
    └─ main4.js
```

## Why?

Original js++ compiler "doesn't like" when there's more then one main file which results in 
problematic situation when you have several "main" files for separate pages. Which leads to
making build script where you need to keep trach of each module you include per file.

`jsppext` is basic solution for that. It goes through all files in source and records all 
imports and all module declarations and automatically constructs a command for js++ compiler.

For example if you have main file `main.jpp` which imports `System`, `Custom.Foo` and `Custom.Bar`, where `Custom.Bar` imports `Custom.Foo` and `Custom.Baz`, `Custom.Foo` and `Custom.Baz` doesn't import anything and you have unused `Custom.Faz`, `jspp src/ -o js/` is going to construct a command `js++ src/main.jpp src/custom/foo.jpp src/custom/bar.jpp src/custom/baz.jpp -o js/main.js`. This output command includes only main file, modules that this main file imports and modules that imported in modules (accounted for recursion). And so, even if you have many main files, `jsppext` is going to pick only things that is needed.
