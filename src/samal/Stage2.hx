package samal;

import haxe.ds.GenericStack;
import haxe.Exception;
import samal.Datatype.DatatypeHelpers;
import samal.AST;
import samal.SamalAST;
import samal.Util;
import samal.Datatype;
using samal.Util.NullTools;
using samal.Datatype.DatatypeHelpers;
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
        } else if(Std.downcast(astNode, SamalFunctionDeclarationNode) != null) {
            mScopeStack.add(new Map<String, VarDeclaration>());
            var node = Std.downcast(astNode, SamalFunctionDeclarationNode);
            for(param in node.getParams()) {
                mScopeStack.first().sure().set(param.getName(), new VarDeclaration(param.getName(), param.getDatatype()));
            }
        }
    }

    function postorder(astNode : ASTNode) {
        if(Std.downcast(astNode, SamalScope) != null) {
            var node = Std.downcast(astNode, SamalScope);
            var stmt = node.getStatements();
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
            mScopeStack.pop();

        } else if(Std.downcast(astNode, SamalBinaryExpression) != null) {
            var node = Std.downcast(astNode, SamalBinaryExpression);
            if(node.getLhs().getDatatype() != node.getRhs().getDatatype()) {
                throw new Exception('${node.errorInfo()} Lhs and rhs types aren\' equal. Lhs is ${node.getLhs().getDatatype().sure()}, rhs is ${node.getRhs().getDatatype().sure()}');
            }
            if(!([Int].contains(node.getLhs().getDatatype().sure()))) {
                throw new Exception('${node.errorInfo()} The ${node.getOperator()} operator is only defined for integers, not for ${node.getLhs().getDatatype().sure()}');
            }
            if([Less, LessEqual, More, MoreEqual].contains(node.getOperator())) {
                node.setDatatype(Datatype.Bool);
            } else {
                node.setDatatype(node.getLhs().getDatatype().sure());
            }

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
        } else if(Std.downcast(astNode, SamalFunctionCallExpression) != null) {
            var node = Std.downcast(astNode, SamalFunctionCallExpression);
            node.setDatatype(node.getFunction().getDatatype().sure().getReturnType());
        }
    }

    function findIdentifier(name : String) : VarDeclaration {
        // search in local scope
        var stackCopy = new GenericStack<Map<String, VarDeclaration>>();
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

        // search in global scope
        var func = mProgram.findFunction(name, mCurrentModule);
        return new VarDeclaration(func.getIdentifier().mangled(), func.getDatatype());
    }

    public function completeDatatypes() : SamalProgram {
        mProgram.forEachModule(function (moduleName : String, ast : ASTNode) {
            mCurrentModule = moduleName;
            ast.traverse(preorder, postorder);
        });
        return mProgram;
    }
}