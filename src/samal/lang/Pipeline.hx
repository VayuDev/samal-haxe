package samal.lang;

import haxe.Resource;
import haxe.Exception;
import samal.lang.targets.JSTarget;
import samal.lang.targets.CppTarget;
import samal.lang.Program;
import haxe.Log;
#if sys
import sys.FileSystem;
import sys.io.File;
#end
#if js
import js.Lib;
#end

// If any string parameter is empty, the resulting files are returned from generate
enum TargetType {
    // Generate a single JS file
    JSSingleFile();
    // Generates a list of C++ files
    CppFiles();
}

class GeneratedFile {
    public var name(default,null) : String;
    public var content(default,null) : String;
    public function new(name : String, content : String) {
        this.name = name;
        this.content = content;
    }
}

class Pipeline {
    var mProgram : SamalProgram;
    final mTarget : TargetType;

    public function new(target : TargetType) {
        mProgram = new SamalProgram();
        mTarget = target;
    }
    public function add(fileName, sourceCode) {
        final parser = new Parser(fileName, sourceCode);
        var ast = parser.parse();
        mProgram.addModule(ast);
    }
    public function generate(mainFunction : String) : Array<GeneratedFile> {
        Log.trace("@@@@ Stage 1 @@@@", null);
        var stage1 = new Stage1(mProgram);
        mProgram = stage1.completeGlobalIdentifiers();
        Log.trace(mProgram.dump(), null);
    
        Log.trace("@@@@ Stage 2 @@@@", null);
        var stage2 = new Stage2(mProgram);
        mProgram = stage2.completeDatatypes();
        Log.trace(mProgram.dump(), null);
    
        Log.trace("@@@@ Stage 3 @@@@", null);
        final target = if(mTarget.match(CppFiles)) {
            new CppTarget();
        } else {
            new JSTarget();
        }
        var stage3 = new Stage3(mProgram, target);
        var cprogram = stage3.convertToCppAST();
        Log.trace(cprogram.dump(), null);
    
        var mainFunction = Util.mangle(mainFunction, []);

        final genJs = function() {
            var res = "// samal runtime (always the same):\n";
            res += Resource.getString("samal_runtime.js");
            res += "\n";
            cprogram.forEachModule(function(mod, ast) {
                res += '// $mod: \n';
                res += ast.toSrc(target, new JSContext(0, mainFunction, Datatypes, cprogram));
                res += ast.toSrc(target, new JSContext(0, mainFunction, Functions, cprogram));
                res += "\n\n";
            });
            return res;
        }

        switch(mTarget) {
            case CppFiles:
                var ret = [];
                cprogram.forEachModule(function(mod, ast) {
                    ret.push(new GeneratedFile(mod + ".hpp", 
                        ast.toSrc(target, new CppContext(0, mainFunction, HeaderOrSource.HeaderStart, cprogram))
                        + ast.toSrc(target, new CppContext(0, mainFunction, HeaderOrSource.HeaderEnd, cprogram))));
                    ret.push(new GeneratedFile(mod + ".cpp", ast.toSrc(target, new CppContext(0, mainFunction, HeaderOrSource.Source, cprogram))));
                });
                ret.push(new GeneratedFile("samal_runtime.cpp", Resource.getString("samal_runtime.cpp")));
                ret.push(new GeneratedFile("samal_runtime.hpp", Resource.getString("samal_runtime.hpp")));
                return ret;
            case JSSingleFile:
                return [new GeneratedFile("out.js", genJs())];
        }
        return [];
        /*cprogram.forEachModule(function(mod, ast) {
          try {
            FileSystem.createDirectory("out");
          } catch(_) {}
          File.saveContent('out/${mod}.js', ast.toSrc(target, new JSContext(0, mainFunction, JSExecutionType.Node)));
    
        });
        File.copy("samal_runtime/samal_runtime.js", "out/samal_runtime.js");*/
    }
}