package samal;

import samal.Datatype.DatatypeHelpers;
import haxe.ds.GenericStack;
import haxe.Exception;
import samal.CppAST;
import samal.SamalAST;
import samal.Program;
import samal.Util.NullTools;
using samal.Util.NullTools;

class Stage3 {
    var mSProgram : SamalProgram;
    var mCProgram : CppProgram;
    var mCurrentModuleName : String = "";
    var mCurrentFileDeclarations : Array<CppDeclaration> = [];
    var mScopeStack : GenericStack<CppScopeNode>;
    var mTempVarNameCounter = 0;

    public function new(prog : SamalProgram) {
        mSProgram = prog;
        mCProgram = new CppProgram("");
        mScopeStack = new GenericStack<CppScopeNode>();
    }

    function genTempVarName(prefix : String) {
        return prefix + "_" + mTempVarNameCounter++;
    }

    function addStatement(stmt : CppStatement) {
        mScopeStack.first().sure().addStatement(stmt);
        return stmt;
    }

    function traverse(astNode : SamalASTNode) : String {
        if(Std.downcast(astNode, SamalFunctionDeclarationNode) != null) {
            var node = Std.downcast(astNode, SamalFunctionDeclarationNode);
            var scope = new CppScopeNode(node.getSourceRef());
            mScopeStack.add(scope);

            var lastStatementResult = "";
            for(stmt in node.getBody().getStatements()) {
                lastStatementResult = traverse(stmt);
            }
            if(lastStatementResult != "") {
                scope.addStatement(new CppReturnStatement(node.getSourceRef(), DatatypeHelpers.getReturnType(node.getDatatype()), lastStatementResult));
            }
            
            mCurrentFileDeclarations.push(new CppFunctionDeclaration(node.getSourceRef(), node.getDatatype(), node.getIdentifier().getName(), node.getParams(), scope));
            mScopeStack.pop();
        } else if(Std.downcast(astNode, SamalScope) != null) {
            var node = Std.downcast(astNode, SamalScope);
            for(child in node.getStatements()) {
                traverse(child);
            }
        } else if(Std.downcast(astNode, SamalScopeExpression) != null) {
            var node = Std.downcast(astNode, SamalScopeExpression);
            
            var resultDeclaration = addStatement(new CppAssignmentStatement(node.getSourceRef(), node.getDatatype().sure(), genTempVarName("scope"), "", CppAssignmentType.JustDeclare));
            

            var scope = new CppScopeStatement(node.getSourceRef(), node.getDatatype().sure(), resultDeclaration.getVarName());
            mScopeStack.add(scope.getScope());
            var lastStatementResult = "";
            for(stmt in node.getScope().getStatements()) {
                lastStatementResult = traverse(stmt);
            }
            addStatement(new CppAssignmentStatement(node.getSourceRef(), node.getDatatype().sure(), resultDeclaration.getVarName(), lastStatementResult, CppAssignmentType.JustAssign));
            mScopeStack.pop();

            addStatement(scope);

            return scope.getVarName();
        } else if(Std.downcast(astNode, SamalBinaryExpression) != null) {
            var node = Std.downcast(astNode, SamalBinaryExpression);
            final lhsVarName = traverse(node.getLhs());
            final rhsVarName = traverse(node.getRhs());
            
            var res : CppStatement;
            switch(node.getOperator()) {
                case Add:
                    res = addStatement(new CppNumericMathStatement(node.getSourceRef(), node.getDatatype().sure(), genTempVarName("binary_expr"), lhsVarName, CppNumericMathOp.Add, rhsVarName));
                case _:
                    throw new Exception("TODO! " + node.dump);
            }
            
            return res.getVarName();
        } else if(Std.downcast(astNode, SamalLiteralIntExpression) != null) {
            var node = Std.downcast(astNode, SamalLiteralIntExpression);
            return Std.string(node.getValue());
        } else {
            throw new Exception("TODO! " + Type.getClassName(Type.getClass(astNode)));
        }
        return "";
    }

    public function convertToCppAST() : CppProgram {
        mCProgram = new CppProgram(mSProgram.getName());
        
        mSProgram.forEachModule(function(moduleName : String, ast : SamalModuleNode) {
            mCurrentModuleName = moduleName;
            mCurrentFileDeclarations = [];
            mScopeStack = new GenericStack<CppScopeNode>();
            for(decl in ast.getDeclarations()) {
                traverse(decl);
            }
            mCProgram.addModule(moduleName, new CppFile(ast.getSourceRef(), mCurrentFileDeclarations));
        });

        return mCProgram;
    }
}