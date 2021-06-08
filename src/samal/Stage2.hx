package samal;

import haxe.Exception;
import samal.Datatype.DatatypeHelpers;
import samal.AST;
import samal.SamalAST;
import samal.Util;
import samal.Datatype;
using samal.Util.NullTools;

class Stage2 {

    var mProgram : Program;
    public function new(prog : Program) {
        mProgram = prog;
    }

    function preorder(node : ASTNode) {
        
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
        } else if(Std.downcast(astNode, SamalFunctionDeclarationNode) != null) {
            var node = Std.downcast(astNode, SamalFunctionDeclarationNode);
            if(DatatypeHelpers.getReturnType(node.getDatatype()) != node.getBody().getDatatype()) {
                throw new Exception(node.errorInfo() + "Expected return type " + DatatypeHelpers.getReturnType(node.getDatatype()) + ", got: " + node.getBody().getDatatype().sure());
            }
        } else if(Std.downcast(astNode, SamalBinaryExpression) != null) {
            var node = Std.downcast(astNode, SamalBinaryExpression);
            node.setDatatype(node.getLhs().getDatatype().sure());
        }
    }

    public function completeDatatypes() : Program {
        mProgram.forEachModule(function (moduleName : String, ast : ASTNode) {
            ast.traverse(preorder, postorder);
        });
        return mProgram;
    }
}