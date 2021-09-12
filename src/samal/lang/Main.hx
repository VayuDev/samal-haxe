package samal.lang;

import haxe.Exception;
import samal.lang.Pipeline;

typedef ParamInfo = {shortVersion : String, longVersion : String, description : String, hasParam : Bool}

class Main {
  static function parseFlags(args : Array<String>, shortVersionsToLongVersions : Array<ParamInfo>) : Map<String, String> {
    final ret : Map<String, String> = new Map();
    var i = 0;
    final isNextArgNotAFlag = function() : Bool {
      return i + 1 < args.length && args[i + 1].length > 0 && args[i + 1].charAt(0) != "-";
    }
    final saveFoundArgToRet = function(longVersion : String, value : String) : Void {
      if(ret.exists(longVersion)) {
        throw new Exception("Parameter " + longVersion + " is set twice!");
      }
      ret.set(longVersion, value);
    }
    while(i < args.length) {
      final part = args[i];
      if(part.length < 2) {
        throw new Exception("Each flag arg must have at least 2 characters!");
      }
      if(part.charAt(0) != "-") {
        throw new Exception("All flags must start with a dash!");
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
    return ret;
  }
  static public function printHelp(paramInfo : Array<ParamInfo>) : Void {
    Util.println('This is the compiler for samal, the Simple And Memory-Wasting Awesomely-Functional Language
Created by VayuDev <vayudev@protonmail.com>. Official homepage at https://samal.dev. Licensed under the MIT license.

Usage: samal [Subcommand] [Options]

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
      Util.println('\t-${row.shortVersion}  --${row.longVersion}\t${row.description}');
    }
    Util.println("\nNot all options are available for all subcommands.\n");
  }
  static function main() {
    final paramInfo = [
      {shortVersion: "l", longVersion: "language", description: "The target language for samal; currently either js or c++", hasParam: true},
      {shortVersion: "h", longVersion: "help", description: "Print this help message", hasParam : false}
    ];
    if(Sys.args()[0] == "-h" || Sys.args()[0] == "--help" || Sys.args()[0] == "-help" || Sys.args()[0] == "help") {
      printHelp(paramInfo);
      Sys.exit(0);
    }
    var flags : Map<String, String> = new Map();
    try {
      flags = parseFlags(Sys.args().slice(1), paramInfo);
    } catch(e : Exception) {
      printHelp(paramInfo);
      Util.println("Error: " + e.message);
      Sys.exit(1);
    }
    if(flags.get("help") != null) {
      printHelp(paramInfo);
      Sys.exit(0);
    }
    switch(Sys.args()[0]) {
      case "transpile":

      case "build":

        trace(flags);
      case "run":

      default:
        printHelp(paramInfo);
        Util.println("Unkown subcommand: " + Sys.args()[0]);
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

