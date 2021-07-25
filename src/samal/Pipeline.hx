package samal;

import haxe.Exception;
import samal.targets.JSTarget;
import samal.targets.CppTarget;
import samal.Program;
import haxe.Log;
#if sys
import sys.FileSystem;
import sys.io.File;
#end
#if js
import js.Lib;
#end

import samal.generated.Runtimes;

// If any string parameter is empty, the resulting files are returned from generate
enum TargetType {
    // Generate a single JS file
    JSSingleFile(outFile : String);
    // Generates a list of C++ files that will be compiled with compiler (clang or gcc recommended)
    CppFiles(outPath : String, compiler : String);
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
        final target = if(mTarget.match(CppFiles(_, _))) {
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
            res += Embedded_samal_runtime_js.getContent();
            res += "\n";
            cprogram.forEachModule(function(mod, ast) {
                res += '// $mod: \n';
                res += ast.toSrc(target, new JSContext(0, mainFunction, Datatypes));
                res += ast.toSrc(target, new JSContext(0, mainFunction, Functions));
                res += "\n\n";
            });
            return res;
        }

        switch(mTarget) {
            case CppFiles(outPath, compiler):
                if(outPath == "" || compiler == "") {
                    var ret = [];
                    cprogram.forEachModule(function(mod, ast) {
                        ret.push(new GeneratedFile(mod + ".hpp", ast.toSrc(target, new CppContext(0, HeaderOrSource.Header, mainFunction))));
                        ret.push(new GeneratedFile(mod + ".cpp", ast.toSrc(target, new CppContext(0, HeaderOrSource.Source, mainFunction))));
                    });
                    ret.push(new GeneratedFile("samal_runtime.cpp", Embedded_samal_runtime_cpp.getContent()));
                    ret.push(new GeneratedFile("samal_runtime.hpp", Embedded_samal_runtime_hpp.getContent()));
                    return ret;
                } else {
                #if sys
                    cprogram.forEachModule(function(mod, ast) {
                        try {
                            FileSystem.createDirectory(outPath);
                        } catch(_) {}
            
                        File.saveContent('${outPath}/${mod}.hpp', ast.toSrc(target, new CppContext(0, HeaderOrSource.Header, mainFunction)));
                        File.saveContent('${outPath}/${mod}.cpp', ast.toSrc(target, new CppContext(0, HeaderOrSource.Source, mainFunction)));
                    });
                    File.saveContent('${outPath}/samal_runtime.hpp', Embedded_samal_runtime_hpp.getContent());
                    File.saveContent('${outPath}/samal_runtime.cpp', Embedded_samal_runtime_cpp.getContent());
                #else
                    throw new Exception("Can't write to FS in non-sys targets!");                
                #end
                }
            case JSSingleFile(""):
                return [new GeneratedFile("out.js", genJs())];

            case JSSingleFile(outFile):
            #if sys
                File.saveContent(outFile, genJs());
            #else
                throw new Exception("Can't write to disk on non-sys targets!");
            #end
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