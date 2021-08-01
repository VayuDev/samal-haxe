package samal;

import samal.Datatype;
import haxe.Exception;
import samal.SamalAST;
import samal.CppAST.CppASTNode;
import samal.CppAST.CppFile;
import samal.SamalAST.SamalModuleNode;
import samal.SamalAST.SamalASTNode;
import samal.AST;
using samal.Util.NullTools;
using samal.Datatype.DatatypeHelpers;

class StringToDatatypeMapperUsingSamalProgram extends StringToDatatypeMapper {
    final mProgram : SamalProgram;
    final mModuleScope : String;
    public function new(program : SamalProgram, moduleScope : String) {
        mProgram = program;
        mModuleScope = moduleScope;
    }
    public function getDatatype(name : String) : Datatype {
        return mProgram.findDatatype(name, mModuleScope).getDatatype();
    }
}

class SamalProgram {
    var mModules = new Map<String, SamalModuleNode>();
    public function new() {
    }

    public function addModule(ast : SamalModuleNode) : Void {
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

    public function forEachModule(callback : (String, SamalModuleNode) -> Void) {
        for(mod in mModules.keyValueIterator()) {
            callback(mod.key, mod.value);
        }
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
    public function findDatatype(name : String, moduleScope : String) : SamalDatatypeDeclaration {
        for(decl in mModules[moduleScope].sure().getDeclarations()) {
            //trace(decl.getName());
            if(decl.getName().substr(decl.getName().lastIndexOf(".") + 1) == name && Std.downcast(decl, SamalDatatypeDeclaration) != null) {
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
    public function makeStringToDatatypeMapper(moduleScope : String) : StringToDatatypeMapper {
        return new StringToDatatypeMapperUsingSamalProgram(this, moduleScope);
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

    public function forEachModule(callback : (String, CppASTNode) -> Void) {
        for(mod in mModules.keyValueIterator()) {
            callback(mod.key, mod.value);
        }
    }
}