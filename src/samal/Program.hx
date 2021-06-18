package samal;

import haxe.Exception;
import samal.SamalAST.SamalFunctionDeclarationNode;
import samal.CppAST.CppASTNode;
import samal.CppAST.CppFile;
import samal.SamalAST.SamalModuleNode;
import samal.SamalAST.SamalASTNode;
import samal.AST;
using samal.Util.NullTools;

class SamalProgram {
    var mModules = new Map<String, SamalModuleNode>();
    var mName : String;
    public function new(name : String) {
        mName = name;
    }

    public function addModule(ast : SamalModuleNode) : Void {
        mModules.set(ast.getModuleName(), ast);
    }

    public function dump() : String {
        var ret = "Program " + mName + ":\n";
        for(mod in mModules.keyValueIterator()) {
            ret += "## " + mod.key + " ##\n";
            ret += mod.value.dump();
        }
        return ret;
    }

    public function forEachModule(callback : (String, SamalModuleNode) -> Void) {
        for(mod in mModules.keyValueIterator()) {
            callback(mod.key, mod.value);
        }
    }

    public function getName() {
        return mName;
    }

    public function findFunction(functionName : String, moduleScope : String) : SamalFunctionDeclarationNode {
        for(decl in mModules[moduleScope].sure().getDeclarations()) {
            //trace(decl.getName());
            if(decl.getName().substr(decl.getName().lastIndexOf(".") + 1) == functionName && Std.downcast(decl, SamalFunctionDeclarationNode) != null) {
                return Std.downcast(decl, SamalFunctionDeclarationNode);
            }
        }
        throw new Exception('Function $functionName not found!');
    }
}
class CppProgram {
    var mModules = new Map<String, CppFile>();
    var mName : String;
    public function new(name : String) {
        mName = name;
    }

    public function addModule(name : String, ast : CppFile) : Void {
        mModules.set(name, ast);
    }

    public function dump() : String {
        var ret = "Cpp Program " + mName + ":\n";
        for(mod in mModules.keyValueIterator()) {
            ret += "## " + mod.key + " ##\n";
            ret += mod.value.dump();
        }
        return ret;
    }

    public function forEachModule(callback : (String, CppASTNode) -> Void) {
        for(mod in mModules.keyValueIterator()) {
            callback(mod.key, mod.value);
        }
    }
}