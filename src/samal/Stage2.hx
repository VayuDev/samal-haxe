package samal;

import haxe.ds.GenericStack;
import haxe.Exception;
import samal.Datatype.DatatypeHelpers;
import samal.AST;
import samal.SamalAST;
import samal.Util;
import samal.Datatype;
using samal.Util.NullTools;
import samal.Program;


class VarDeclaration {
    var mName : String;
    var mType : Datatype;
    public function new(name : String, type : Datatype) {
        mName = name;
        mType = type;
    }
    public function getIdentifier() {
        return mName;
    }
    public function getType() {
        return mType;
    }
}

class Stage2 {
    var mProgram : SamalProgram;
    var mScopeStack : GenericStack<Map<String, VarDeclaration>> = new GenericStack();
    var mCurrentModule : String = "";

    public function new(prog : SamalProgram) {
        mProgram = prog;
    }

    function preorder(astNode : ASTNode) {
        if(Std.downcast(astNode, SamalScope) != null) {
            mScopeStack.add(new Map<String, VarDeclaration>());
        }
    }

    function postorder(astNode : ASTNode) {
        if(Std.downcast(astNode, SamalScope) != null) {
            var node = Std.downcast(astNode, SamalScope);
            var stmt = node.getStatements();
            trace(stmt[stmt.length - 1].getDatatype());
            if(stmt.length == 0) {
                node.setDatatype(Datatype.Tuple([]));
            } else {
                node.setDatatype(stmt[stmt.length - 1].getDatatype().sure());
            }
            mScopeStack.pop();
        } else if(Std.downcast(astNode, SamalFunctionDeclarationNode) != null) {
            var node = Std.downcast(astNode, SamalFunctionDeclarationNode);
            if(DatatypeHelpers.getReturnType(node.getDatatype()) != node.getBody().getDatatype()) {
                throw new Exception(
                    node.errorInfo() 
                    + "Expected return type " 
                    + DatatypeHelpers.getReturnType(node.getDatatype()) 
                    + ", got: " 
                    + node.getBody().getDatatype().sure());
            }
            node.setIdentifier(new IdentifierWithTemplate(mCurrentModule + "." + node.getIdentifier().getName(), node.getIdentifier().getTemplateParams()));

        } else if(Std.downcast(astNode, SamalBinaryExpression) != null) {
            var node = Std.downcast(astNode, SamalBinaryExpression);
            node.setDatatype(node.getLhs().getDatatype().sure());

        } else if(Std.downcast(astNode, SamalAssignmentExpression) != null) {
            var node = Std.downcast(astNode, SamalAssignmentExpression);
            node.setDatatype(node.getRhs().getDatatype().sure());
            var decl : VarDeclaration;
            if(mScopeStack.first().sure().exists(node.getIdentifier())) {
                // shadowing
                // get shadow amount
                var nameStr = mScopeStack.first().sure()[node.getIdentifier()].sure().getIdentifier();
                var indexOfDollar = nameStr.lastIndexOf("$");
                var newShadowAmount : Int = 0;
                if(indexOfDollar == -1) {
                    newShadowAmount = 1;
                } else {
                    newShadowAmount = Std.parseInt(nameStr.substr(indexOfDollar + 1)).sure() + 1;
                }
                decl = new VarDeclaration(node.getIdentifier() + "$" + newShadowAmount, node.getDatatype().sure());
            } else {
                decl = new VarDeclaration(node.getIdentifier(), node.getDatatype().sure());
            }
            mScopeStack.first().sure().set(node.getIdentifier(), decl);
            node.setIdentifier(decl.getIdentifier());

        } else if(Std.downcast(astNode, SamalLoadIdentifierExpression) != null) {
            var node = Std.downcast(astNode, SamalLoadIdentifierExpression);
            if(node.getIdentifier().getTemplateParams().length == 0) {
                var decl = findIdentifier(node.getIdentifier().getName());
                node.setIdentifier(new IdentifierWithTemplate(decl.getIdentifier(), []));
                node.setDatatype(decl.getType());
            }
        } 
    }

    function findIdentifier(name : String) : VarDeclaration {
        var stackCopy = new GenericStack();
        for(frame in mScopeStack) {
            stackCopy.add(frame);
        }
        while(!stackCopy.isEmpty()) {
            var type = stackCopy.first().sure().get(name);
            if(type != null) {
                return type;
            }
            stackCopy.pop();
        }

        throw new Exception("Variable $name not found!");
    }

    public function completeDatatypes() : SamalProgram {
        mProgram.forEachModule(function (moduleName : String, ast : ASTNode) {
            mCurrentModule = moduleName;
            ast.traverse(preorder, postorder);
        });
        return mProgram;
    }
}