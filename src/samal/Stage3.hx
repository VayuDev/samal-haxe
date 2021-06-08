package samal;

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
    }

    function traverse(astNode : SamalASTNode) : String {
        if(Std.downcast(astNode, SamalFunctionDeclarationNode) != null) {
            var node = Std.downcast(astNode, SamalFunctionDeclarationNode);
            var scope = new CppScopeNode(node.getSourceRef());
            mScopeStack.add(scope);
            traverse(node.getBody());
            
            mCurrentFileDeclarations.push(new CppFunctionDeclaration(node.getSourceRef(), node.getDatatype(), node.getIdentifier().getName(), node.getParams(), scope));
            mScopeStack.pop();
        } else if(Std.downcast(astNode, SamalDumbScope) != null) {
            var node = Std.downcast(astNode, SamalDumbScope);
            for(child in node.getStatements()) {
                traverse(child);
            }
        } else if(Std.downcast(astNode, SamalBinaryExpression) != null) {
            var node = Std.downcast(astNode, SamalBinaryExpression);
            final lhsVarName = traverse(node.getLhs());
            final rhsVarName = traverse(node.getRhs());
            
            var resName = genTempVarName("binary_expr");
            switch(node.getOperator()) {
                case Add:
                    addStatement(new CppNumericMathStatement(node.getSourceRef(), resName, lhsVarName, CppNumericMathOp.Add, rhsVarName));
                case _:
                    throw new Exception("TODO! " + node.dump);
            }
            
            return resName;
        } else if(Std.downcast(astNode, SamalLiteralIntExpression) != null) {
            var node = Std.downcast(astNode, SamalLiteralIntExpression);
            return "" + node.getValue();
        }else {
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