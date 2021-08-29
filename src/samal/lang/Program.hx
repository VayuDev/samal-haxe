package samal.lang;

import samal.lang.CppAST;
import samal.lang.Datatype;
import haxe.Exception;
import samal.lang.generated.SamalAST;
import samal.lang.CppAST.CppASTNode;
import samal.lang.CppAST.CppFile;
import samal.lang.generated.SamalAST.SamalModule;
import samal.lang.generated.SamalAST.SamalASTNode;
import samal.lang.AST;
using samal.lang.Util.NullTools;
using samal.lang.Datatype.DatatypeHelpers;

class SamalProgram {
    var mModules = new Map<String, SamalModule>();
    public function new() {
    }

    public function addModule(ast : SamalModule) : Void {
        mModules.set(ast.getModuleName(), ast);
    }

    public function dump() : String {
        var ret = "Program:\n";
        for(mod in mModules.keyValueIterator()) {
            ret += "## " + mod.key + " ##\n";
            ret += mod.value.dump();
        }
        return ret;
    }

    public function forEachModule(callback : (String, SamalModule) -> Void) {
        for(mod in mModules.keyValueIterator()) {
            callback(mod.key, mod.value);
        }
    }

    public function getModule(name : String) : Null<SamalModule> {
        return mModules[name];
    }

    public function findFunction(functionName : String, moduleScope : String) : SamalFunctionDeclaration {
        for(decl in mModules[moduleScope].sure().getDeclarations()) {
            //trace(decl.getName());
            if(decl.getName().getName().substr(decl.getName().getName().lastIndexOf(".") + 1) == functionName && Std.downcast(decl, SamalFunctionDeclaration) != null) {
                return Std.downcast(decl, SamalFunctionDeclaration);
            }
        }
        throw new Exception('Function $functionName not found!');
    }
    public function findDatatypeUsingNameAndScope(name : String, moduleScope : String) : SamalDatatypeDeclaration {
        for(decl in mModules[moduleScope].sure().getDeclarations()) {
            //trace(decl.getName());
            if(decl.getName().getName().substr(decl.getName().getName().lastIndexOf(".") + 1) == name && Std.isOfType(decl, SamalDatatypeDeclaration)) {
                return Std.downcast(decl, SamalDatatypeDeclaration);
            }
        }
        throw new DatatypeNotFound(name);
    }
    public function findDatatypeDeclaration(datatype : Datatype) : SamalDatatypeDeclaration {
        for(mod in mModules) {
            for(decl in mod.getDeclarations()) {
                final typeDecl = Std.downcast(decl, SamalDatatypeDeclaration);
                if(typeDecl != null && typeDecl.getDatatype().deepEquals(datatype)) {
                    return typeDecl;
                }
            }
        }
        throw new Exception("Datatype " + datatype + " not found!");
    }
}
class CppProgram {
    var mModules = new Map<String, CppFile>();
    public function new() {
    }

    public function addModule(name : String, ast : CppFile) : Void {
        mModules.set(name, ast);
    }

    public function dump() : String {
        var ret = "Cpp Program:\n";
        for(mod in mModules.keyValueIterator()) {
            ret += "## " + mod.key + " ##\n";
            ret += mod.value.dump();
        }
        return ret;
    }

    public function forEachModule(callback : (String, CppFile) -> Void) {
        for(mod in mModules.keyValueIterator()) {
            callback(mod.key, mod.value);
        }
    }
    public function findUsertypeDeclaration(datatype : Datatype) : CppUsertypeDeclaration {
        for(mod in mModules) {
            for(decl in mod.getDeclarations()) {
                final typeDecl = Std.downcast(decl, CppUsertypeDeclaration);
                if(typeDecl != null && typeDecl.getDatatype().deepEquals(datatype)) {
                    return typeDecl;
                }
            }
        }
        throw new Exception("Datatype " + datatype + " not found!");
    }
}