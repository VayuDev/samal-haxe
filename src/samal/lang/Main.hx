package samal.lang;

import sys.FileSystem;
import sys.io.File;
import haxe.Exception;
import samal.lang.Pipeline;

using samal.lang.Util.NullTools;

typedef ParamInfo = {shortVersion : String, longVersion : String, description : String, hasParam : Bool}

enum TranspileAndWriteToDiskMode {
  NormalJustTranspile;
  DisallowStdoutForCpp;
  DisallowStdoutForAll;
}

class Main {
  static function parseFlags(args : Array<String>, shortVersionsToLongVersions : Array<ParamInfo>) : {flags: Map<String, String>, rest: Array<String>} {
    final ret : Map<String, String> = new Map();
    var i = 0;
    final isNextArgNotAFlag = function() : Bool {
      return i + 1 < args.length && args[i + 1].length > 0 && (args[i + 1].charAt(0) != "-" || args[i + 1].charAt(0) == "-");
    }
    final saveFoundArgToRet = function(longVersion : String, value : String) : Void {
      if(ret.exists(longVersion)) {
        throw new Exception("Parameter " + longVersion + " is set twice!");
      }
      ret.set(longVersion, value);
    }
    while(i < args.length) {
      final part = args[i];
      if(part.length < 2 || part.charAt(0) != "-") {
        return {flags: ret, rest: args.slice(i)};
      }
      if(part == "--") {
        return {flags: ret, rest: args.slice(i + 1)};
      }
      if(part.charAt(1) == "-") {
        final longArg = args[i].substr(2);
        var paramInfo : Null<ParamInfo>  = null;
        for(param in shortVersionsToLongVersions) {
          if(param.longVersion == longArg) {
            paramInfo = param;
            break;
          }
        }
        if(paramInfo == null) {
          throw new Exception("Unkonwn flag " + args[i].substr(2));
        }
        if(isNextArgNotAFlag()) {
          if(!paramInfo.hasParam) {
            throw new Exception('-${paramInfo.shortVersion}  --${paramInfo.longVersion} doesn\'t accept a parameter');
          }
          saveFoundArgToRet(longArg, args[i + 1]);
          i += 1;
        } else {
          saveFoundArgToRet(longArg, "");
        }
      } else {
        // short args
        for(j in 1...args[i].length) {
          var paramInfo : Null<ParamInfo> = null;
          for(param in shortVersionsToLongVersions) {
            if(param.shortVersion == args[i].charAt(j)) {
              paramInfo = param;
              break;
            }
          }
          if(paramInfo == null) {
            throw new Exception("Unkonwn flag " + args[i].substr(2));
          }
          if(j == args[i].length - 1 && isNextArgNotAFlag()) {
            // parameterized arg
            if(!paramInfo.hasParam) {
              throw new Exception('-${paramInfo.shortVersion}  --${paramInfo.longVersion} doesn\'t accept a parameter');
            }
            saveFoundArgToRet(paramInfo.longVersion, args[i + 1]);
            i += 1;
          } else {
            saveFoundArgToRet(paramInfo.longVersion, "");
          }
        }
      }

      i++;
    }
    return {flags: ret, rest: []};
  }
  static public function printHelp(paramInfo : Array<ParamInfo>) : Void {
    Util.println('This is the compiler for samal, the Simple And Memory-Wasting Awesomely-Functional Language
Created by VayuDev <vayudev@protonmail.com>. Official homepage at https://samal.dev. Licensed under the MIT license.

Usage: samal [Subcommand] [Options] [Files]

Subcommand:
\ttranspile\tGenerate raw C++ or JS code from samal source code
\tbuild\t\tSame as \'transpile\', but with the C++-Target, compile the code as well
\trun\t\tSame as \'build\', but run the result as well
\t\t\tNote: It\'s possible to run the generated JS code from \'build\' on your own,
\t\t\t      but make sure to increase the stack size of your interpreter as most 
\t\t\t      samal programs make heavy use of recursion.

Options:');
    paramInfo.sort(function(a, b) {
      if(a.longVersion < b.longVersion) {
        return -1;
      } else if(a.longVersion > b.longVersion) {
        return 1;
      }
      return 0;
    });
    for(row in paramInfo) {
      if(row.shortVersion != "") {
        Util.println('\t-${row.shortVersion}  --${row.longVersion}\t${row.description}');
      } else {
        Util.println('\t    --${row.longVersion}\t${row.description}');
      }
    }
    Util.println("\nNot all options are available for all subcommands.\n");
  }
  static function main() {
    final paramInfo : Array<ParamInfo> = [
      {shortVersion: "l", longVersion: "language", description: "The target language for samal; currently either js or c++", hasParam: true},
      {shortVersion: "h", longVersion: "help", description: "Print this help message", hasParam : false},
      {shortVersion: "o", longVersion: "output", description: "Output file path for final executable/JS-script; use - for stdout", hasParam : true},
      {
        shortVersion: "", 
        longVersion: "c++-files-dir", 
        description: "Output directory for storing generated C++-Code; use - for stdout, each file starts with // Filename: <filename> (stdout only available with transpile)", 
        hasParam : true
      },
      {shortVersion: "m", longVersion: "main", description: "Full name of the main function, e.g. MyProgram.Main.main", hasParam: true},
      {shortVersion: "d", longVersion: "debug", description: "Print ASTs for debugging purposes", hasParam: false},
      {shortVersion: "c", longVersion: "c++-compiler", description: "The C++-Compiler for building the generated C++-Code; defaults to g++", hasParam: true}
    ];
    if(Sys.args()[0] == "-h" || Sys.args()[0] == "--help" || Sys.args()[0] == "-help" || Sys.args()[0] == "help") {
      printHelp(paramInfo);
      Sys.exit(0);
    }
    final printHelpAndExit = function(statusCode : Int, message : String) : Void {
      printHelp(paramInfo);
      Util.println("Error: " + message);
      Sys.exit(statusCode);
    }
    final parseFlagsRet = try {
      parseFlags(Sys.args().slice(1), paramInfo);
    } catch(e : Exception) {
      printHelpAndExit(1, e.message);
      return;
    }
    final flags = parseFlagsRet.flags;
    if(flags.get("help") != null) {
      printHelp(paramInfo);
      Sys.exit(0);
    }

    final transpile = function() : {target: TargetType, generatedFiles: Array<GeneratedFile>} {
      if(!flags.exists("language")) {
        printHelpAndExit(3, "Error: You must specify a target language using the -l option");
      }
      if(!flags.exists("main")) {
        printHelpAndExit(5, "Error: You must specify a main function using the -m option!");
      }
      var targetType;
      if(flags.get("language").sure() == "c++") {
        targetType = TargetType.CppFiles;
      } else if(flags.get("language").sure() == "js") {
        targetType = TargetType.JSSingleFile;
      } else {
        printHelpAndExit(6, "Error: language must be c++ or js, not: " + flags.get("language").sure());
        throw new Exception(""); // unreachable, but the compiler doesn't know that
      }
      final pipeline = new Pipeline(targetType);
      for(path in parseFlagsRet.rest) {
        final fileHandle = File.read(path);
        final content = fileHandle.readAll().toString();
        fileHandle.close();
        pipeline.add(path, content);
      }
      final generatedFiles = pipeline.generate(flags.get("main").sure());
      
      return {target: targetType, generatedFiles: generatedFiles};
    }

    final transpileAndWriteToDisk = function(mode : TranspileAndWriteToDiskMode) {
      final transpileResult = transpile();
      var cppOutDir = "";
      var cppOutDirIsGenerated = false;
      switch(transpileResult.target) {
        case JSSingleFile:
          if(!flags.exists("output")) {
            printHelpAndExit(4, "You must specify an output path using the -o option!");
          }
          if(flags.get("output").sure() == "-") {
            if(mode == DisallowStdoutForAll) {
              printHelpAndExit(10, "Writing to stdout is not possible in this configuration");
            }
            Util.println(transpileResult.generatedFiles[0].content);
          } else {
            File.saveContent(flags.get("output").sure(), transpileResult.generatedFiles[0].content);
          }
        case CppFiles:
          if(!flags.exists("c++-files-dir") && mode == NormalJustTranspile) {
            // we don't allow randomly generating a dir in this mode because that doesn't really make sense; if you just transpile, then you
            // want a predicatable output location
            throw new Exception("Trying to output generated C++ files to temporary directory without compilation - this doesn't make sense! "
              + "Please specify a target directory using c++-files-dir.");
          }
          if(flags.exists("c++-files-dir") && flags.get("c++-files-dir").sure() == "-") {
            // output to stdout
            if(mode == DisallowStdoutForAll || mode == DisallowStdoutForCpp) {
              printHelpAndExit(10, "Writing to stdout is not possible in this configuration");
            }
            for(file in transpileResult.generatedFiles) {
              Util.println("// Filename: " + file.name);
              Util.println(file.content);
            }
          } else {
            cppOutDir = if(flags.exists("c++-files-dir")) {
              flags.get("c++-files-dir").sure();
            } else {
              // TODO use proper random file gneration
              cppOutDirIsGenerated = true;
              "/tmp/samal-c++-compilation-" + Math.random() + Math.random();
            }
            try {
              FileSystem.createDirectory(cppOutDir);
            } catch(_) {}
            for(file in transpileResult.generatedFiles) {
              File.saveContent(cppOutDir + "/" + file.name, file.content);
            }
          }
      }
      return {transpileResult: transpileResult, cppResultDir: cppOutDir, cppResultDirIsGenerated: cppOutDirIsGenerated};
    }

    try {
      switch(Sys.args()[0]) {
        case "transpile":
          transpileAndWriteToDisk(NormalJustTranspile);
        case "build":
          final result = transpileAndWriteToDisk(DisallowStdoutForCpp);
          if(result.transpileResult.target.match(CppFiles)) {
            final compiler = if(flags.exists("c++-compiler")) {
              flags.get("c++-compiler").sure();
            } else {
              "g++";
            }
            if(!flags.exists("output")) {
              printHelpAndExit(11, "You must specify an output file path to store the executable!");
            }
            Sys.command(compiler, 
              ["-O0", "-g", "-std=c++11", "-o", flags.get("output").sure(), "-lstdc++"]
              .concat(result.transpileResult.generatedFiles.filter(function(f) return f.name.substr(-4) == ".cpp").map(function(f) return result.cppResultDir + "/" + f.name)));
            if(result.cppResultDirIsGenerated) {
              for(f in FileSystem.readDirectory(result.cppResultDir)) {
                FileSystem.deleteFile(result.cppResultDir + "/" + f);
              }
              FileSystem.deleteDirectory(result.cppResultDir);
            }
          }
        case "run":

        default:
          printHelp(paramInfo);
          Util.println("Unkown subcommand: " + Sys.args()[0]);
      }
    } catch(e : Exception) {
      Util.println("Error: " + e.details());
      Sys.exit(2);
    }
    /*
    var pipeline = new Pipeline(TargetType.CppFiles("out", "gcc"));
    pipeline.add("Main", code);
    var files = pipeline.generate("A.B.Main.main");
    #if js
    js.Lib.eval(files[0].content);
    #end*/
  }
}

