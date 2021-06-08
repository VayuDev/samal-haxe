package samal;

import samal.AST;

class Program {
    var mModules = new Map<String, ASTNode>();
    public function new() {

    }

    public function addModule(name : String, ast : ASTNode) : Void {
        mModules.set(name, ast);
    }

    public function dump() : String {
        var ret = "";
        for(mod in mModules.keyValueIterator()) {
            ret += "#### " + mod.key + " ####\n";
            ret += mod.value.dump();
        }
        return ret;
    }

    public function forEachModule(callback : (String, ASTNode) -> Void) {
        for(mod in mModules.keyValueIterator()) {
            callback(mod.key, mod.value);
        }
    }
}