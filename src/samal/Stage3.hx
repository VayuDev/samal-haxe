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
        mCProgram = new CppProgram();
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
            
            mCurrentFileDeclarations.push(new CppFunctionDeclaration(node.getSourceRef(), node.getDatatype(), node.getIdentifier().mangled(), node.getParams(), scope));
            mScopeStack.pop();
        } else if(Std.downcast(astNode, SamalScopeExpression) != null) {
            var node = Std.downcast(astNode, SamalScopeExpression);
            
            var resultDeclaration = addStatement(new CppAssignmentStatement(node.getSourceRef(), node.getDatatype().sure(), genTempVarName("scope"), "", CppAssignmentType.JustDeclare));
            

            var scope = new CppScopeStatement(node.getSourceRef(), node.getDatatype().sure(), resultDeclaration.getVarName());
            mScopeStack.add(scope.getScope());
            var lastStatementResult = "";
            for(stmt in node.getScope().getStatements()) {
                lastStatementResult = traverse(stmt);
            }
            if(lastStatementResult != "") {
                // if it's not after an unreachable node
                addStatement(new CppAssignmentStatement(node.getSourceRef(), node.getDatatype().sure(), resultDeclaration.getVarName(), lastStatementResult, CppAssignmentType.JustAssign));
            }
            mScopeStack.pop();

            addStatement(scope);

            return scope.getVarName();
        } else if(Std.downcast(astNode, SamalBinaryExpression) != null) {
            var node = Std.downcast(astNode, SamalBinaryExpression);
            final lhsVarName = traverse(node.getLhs());
            final rhsVarName = traverse(node.getRhs());
            
            var op : CppBinaryExprOp;
            switch(node.getOperator()) {
                case Add:
                    op = CppBinaryExprOp.Add;
                case Sub:
                    op = CppBinaryExprOp.Sub;
                case Less:
                    op = CppBinaryExprOp.Less;
                case More:
                    op = CppBinaryExprOp.More;
                case LessEqual:
                    op = CppBinaryExprOp.LessEqual;
                case MoreEqual:
                    op = CppBinaryExprOp.MoreEqual;
                
                case _:
                    throw new Exception("TODO! " + node.dump());
            }
            var res = addStatement(new CppBinaryExprStatement(node.getSourceRef(), node.getDatatype().sure(), genTempVarName("binary_expr"), lhsVarName, op, rhsVarName));
            
            return res.getVarName();
        } else if(Std.downcast(astNode, SamalUnaryExpression) != null) {
            var node = Std.downcast(astNode, SamalUnaryExpression);
            var exprVarName = traverse(node.getExpression());
            var op : CppUnaryOp;
            switch(node.getOperator()) {
                case Not:
                    op = CppUnaryOp.Not;
                case _:
                    throw new Exception("TODO! " + node.dump());
            }
            var res = addStatement(new CppUnaryExprStatement(node.getSourceRef(), node.getDatatype().sure(), genTempVarName("unary_expr"), exprVarName, op));
            return res.getVarName();

        } else if(Std.downcast(astNode, SamalSimpleListIsEmpty) != null) {
            var node = Std.downcast(astNode, SamalSimpleListIsEmpty);
            var exprVarName = traverse(node.getList());
            var res = addStatement(new CppUnaryExprStatement(node.getSourceRef(), node.getDatatype().sure(), genTempVarName("list_is_empty"), exprVarName, ListIsEmpty));
            return res.getVarName();

        } else if(Std.downcast(astNode, SamalSimpleListGetHead) != null) {
            var node = Std.downcast(astNode, SamalSimpleListGetHead);
            var exprVarName = traverse(node.getList());
            var res = addStatement(new CppUnaryExprStatement(node.getSourceRef(), node.getDatatype().sure(), genTempVarName("list_get_head"), exprVarName, ListGetHead));
            return res.getVarName();

        } else if(Std.downcast(astNode, SamalSimpleListGetTail) != null) {
            var node = Std.downcast(astNode, SamalSimpleListGetTail);
            var exprVarName = traverse(node.getList());
            var res = addStatement(new CppUnaryExprStatement(node.getSourceRef(), node.getDatatype().sure(), genTempVarName("list_is_empty"), exprVarName, ListGetTail));
            return res.getVarName();

        } else if(Std.downcast(astNode, SamalLiteralIntExpression) != null) {
            var node = Std.downcast(astNode, SamalLiteralIntExpression);
            return "(int32_t) (" + Std.string(node.getValue()) + ")";

        } else if(Std.downcast(astNode, SamalAssignmentExpression) != null) {
            var node = Std.downcast(astNode, SamalAssignmentExpression);
            
            var rhsVarName = traverse(node.getRhs());

            addStatement(new CppAssignmentStatement(node.getSourceRef(), node.getDatatype().sure(), node.getIdentifier(), rhsVarName, CppAssignmentType.DeclareAndAssign));
            return node.getIdentifier();

        } else if(Std.downcast(astNode, SamalLoadIdentifierExpression) != null) {
            var node = Std.downcast(astNode, SamalLoadIdentifierExpression);
            return node.getIdentifier().mangled();
        } else if(Std.downcast(astNode, SamalFunctionCallExpression) != null) {
            var node = Std.downcast(astNode, SamalFunctionCallExpression);
            var functionName = traverse(node.getFunction());

            var params = [];
            for(p in node.getParams()) {
                params.push(traverse(p));
            }
            var destName = genTempVarName("function_result");
            addStatement(new CppFunctionCallStatement(node.getSourceRef(), node.getDatatype().sure(), destName, functionName, params));

            return destName;
        
        } else if(Std.downcast(astNode, SamalSimpleIfExpression) != null) {
            var node = Std.downcast(astNode, SamalSimpleIfExpression);

            final returnVarnmae = genTempVarName("if_result");
            final datatype = node.getDatatype().sure();
            var resultDeclaration = addStatement(new CppAssignmentStatement(node.getSourceRef(), datatype, returnVarnmae, "", CppAssignmentType.JustDeclare));

            var umbrellaScope = new CppScopeStatement(node.getSourceRef(), datatype, returnVarnmae);
            mScopeStack.add(umbrellaScope.getScope());

            var conditionVarName = traverse(node.getMainCondition());

            var mainScope = new CppScopeNode(node.getSourceRef());
            mScopeStack.add(mainScope);
            var lastStatementResult = "";
            for(stmt in node.getMainBody().getStatements()) {
                lastStatementResult = traverse(stmt);
            }
            if(lastStatementResult != "") {
                // if it's not after an unreachable point
                addStatement(new CppAssignmentStatement(node.getSourceRef(), datatype, returnVarnmae, lastStatementResult, CppAssignmentType.JustAssign));
            }
            mScopeStack.pop();

            var elseScope = new CppScopeNode(node.getSourceRef());
            mScopeStack.add(elseScope);
            lastStatementResult = "";
            for(stmt in node.getElseBody().getStatements()) {
                lastStatementResult = traverse(stmt);
            }
            if(lastStatementResult != "") {
                // if it's not after an unreachable point
                addStatement(new CppAssignmentStatement(node.getSourceRef(), datatype, returnVarnmae, lastStatementResult, CppAssignmentType.JustAssign));
            }
            mScopeStack.pop();

            addStatement(new CppIfStatement(node.getSourceRef(), datatype, returnVarnmae, conditionVarName, mainScope, elseScope));

            mScopeStack.pop();
            addStatement(umbrellaScope);
            
            return resultDeclaration.getVarName();

        } else if(Std.downcast(astNode, SamalSimpleCreateEmptyList) != null) {
            var node = Std.downcast(astNode, SamalSimpleCreateEmptyList);
            return "(" + DatatypeHelpers.toCppType(node.getDatatype().sure()) + ") (nullptr)";

        } else if(Std.downcast(astNode, SamalSimpleListPrepend) != null) {
            var node = Std.downcast(astNode, SamalSimpleListPrepend);
            
            var valueVarName = traverse(node.getValue());
            var listVarName = traverse(node.getList());

            var varName = genTempVarName("list_prepend");
            addStatement(new CppListPrependStatement(node.getSourceRef(), node.getDatatype().sure(), varName, valueVarName, listVarName));
            return varName;

        } else if(Std.downcast(astNode, SamalSimpleUnreachable) != null) {
            addStatement(new CppUnreachable(astNode.getSourceRef()));
            return "";

        } else {
            throw new Exception("TODO! " + Type.getClassName(Type.getClass(astNode)));
        }
        return "";
    }

    public function convertToCppAST() : CppProgram {
        mCProgram = new CppProgram();
        
        mSProgram.forEachModule(function(moduleName : String, ast : SamalModuleNode) {
            moduleName = Util.mangle(moduleName, []);
            mCurrentModuleName = moduleName;
            mCurrentFileDeclarations = [];
            mScopeStack = new GenericStack<CppScopeNode>();
            for(decl in ast.getDeclarations()) {
                traverse(decl);
            }
            mCProgram.addModule(moduleName, new CppFile(ast.getSourceRef(), moduleName, mCurrentFileDeclarations));
        });

        return mCProgram;
    }
}