package samal;

import samal.CppAST.CppASTNode;
import samal.CppAST.CppFile;
import samal.SamalAST.SamalModuleNode;
import samal.SamalAST.SamalASTNode;
import samal.AST;

class SamalProgram {
    var mModules = new Map<String, SamalModuleNode>();
    var mName : String;
    public function new(name : String) {
        mName = name;
    }

    public function addModule(name : String, ast : SamalModuleNode) : Void {
        mModules.set(name, ast);
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
}
class CppProgram {
    var mModules = new Map<String, CppFile>();
    var mName : String;
    public function new(name : String) {
        mName = name;
    }

    public function addModule(name : String, ast : CppFile) : Void {
        mModules.set(name, ast);
        mName = name;
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