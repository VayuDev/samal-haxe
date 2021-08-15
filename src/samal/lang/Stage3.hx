package samal.lang;

import samal.lang.targets.LanguageTarget;
import samal.bootstrap.Tokenizer.SourceCodeRef;
import haxe.ds.List;
import samal.lang.Datatype.DatatypeHelpers;
import haxe.ds.GenericStack;
import haxe.Exception;
import samal.lang.CppAST;
import samal.lang.generated.SamalAST;
import samal.lang.Program;
import samal.lang.Util.NullTools;
using samal.lang.Util.NullTools;

class Stage3 {
    var mSProgram : SamalProgram;
    var mCProgram : CppProgram;
    var mCurrentModuleName : String = "";
    var mCurrentFileDeclarations : Array<CppDeclaration> = [];
    var mScopeStack : GenericStack<CppScopeNode>;
    var mTempVarNameCounter = 0;
    var mUsedDatatypes : Array<Datatype> = [];
    final mTarget : LanguageTarget;

    public function new(prog : SamalProgram, target : LanguageTarget) {
        mSProgram = prog;
        mCProgram = new CppProgram();
        mScopeStack = new GenericStack<CppScopeNode>();
        mTarget = target;
    }

    function addUsedDatatype(newType : Datatype) : Datatype {
        for(existingType in mUsedDatatypes) {
            if(existingType.equals(newType)) {
                return newType;
            }
        }
        mUsedDatatypes.push(newType);
        return newType;
    }

    function genTempVarName(prefix : String) {
        return prefix + "_" + mTempVarNameCounter++;
    }

    function addStatement(stmt : CppStatement) {
        mScopeStack.first().sure().addStatement(stmt);
        return stmt;
    }

    function traverse(astNode : SamalASTNode) : String {
        if(Std.downcast(astNode, SamalFunctionDeclaration) != null) {
            var node = Std.downcast(astNode, SamalFunctionDeclaration);
            final functionDatatype = addUsedDatatype(node.getDatatype());
            var scope = new CppScopeNode(node.getSourceRef());
            mScopeStack.add(scope);

            var lastStatementResult = "";
            for(stmt in node.getBody().getStatements()) {
                lastStatementResult = traverse(stmt);
            }
            if(lastStatementResult != "") {
                scope.addStatement(new CppReturnStatement(node.getSourceRef(), DatatypeHelpers.getReturnType(functionDatatype), lastStatementResult));
            }
            
            mCurrentFileDeclarations.push(new CppFunctionDeclaration(node.getSourceRef(), functionDatatype, node.getName().mangled(), node.getParams(), scope));
            mScopeStack.pop();
        } else if(Std.downcast(astNode, SamalStructDeclaration) != null) {
            var node = Std.downcast(astNode, SamalStructDeclaration);
            mCurrentFileDeclarations.push(new CppStructDeclaration(node.getSourceRef(), node.getDatatype(), node.getFields()));

        } else if(Std.downcast(astNode, SamalScopeExpression) != null) {
            var node = Std.downcast(astNode, SamalScopeExpression);
            final nodeDatatype = addUsedDatatype(node.getDatatype().sure());
            
            var resultDeclaration = addStatement(new CppAssignmentStatement(node.getSourceRef(), nodeDatatype, genTempVarName("scope"), "", CppAssignmentType.JustDeclare));
            

            var scope = new CppScopeStatement(node.getSourceRef(), nodeDatatype, resultDeclaration.getVarName());
            mScopeStack.add(scope.getScope());
            var lastStatementResult = "";
            for(stmt in node.getScope().getStatements()) {
                lastStatementResult = traverse(stmt);
            }
            if(lastStatementResult != "") {
                // if it's not after an unreachable node
                addStatement(new CppAssignmentStatement(node.getSourceRef(), nodeDatatype, resultDeclaration.getVarName(), lastStatementResult, CppAssignmentType.JustAssign));
            }
            mScopeStack.pop();

            addStatement(scope);

            return scope.getVarName();
        } else if(Std.downcast(astNode, SamalBinaryExpression) != null) {
            var node = Std.downcast(astNode, SamalBinaryExpression);
            final nodeDatatype = addUsedDatatype(node.getDatatype().sure());
            final lhsVarName = traverse(node.getLhs());
            final rhsVarName = traverse(node.getRhs());
            
            var op : CppBinaryExprOp;
            switch(node.getOp()) {
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
            var res = addStatement(new CppBinaryExprStatement(node.getSourceRef(), nodeDatatype, genTempVarName("binary_expr"), lhsVarName, op, rhsVarName));
            
            return res.getVarName();
        } else if(Std.downcast(astNode, SamalUnaryExpression) != null) {
            var node = Std.downcast(astNode, SamalUnaryExpression);
            final nodeDatatype = addUsedDatatype(node.getDatatype().sure());
            var exprVarName = traverse(node.getExpr());
            var op : CppUnaryOp;
            switch(node.getOp()) {
                case Not:
                    op = CppUnaryOp.Not;
                case _:
                    throw new Exception("TODO! " + node.dump());
            }
            var res = addStatement(new CppUnaryExprStatement(node.getSourceRef(), nodeDatatype, genTempVarName("unary_expr"), exprVarName, op));
            return res.getVarName();

        } else if(Std.downcast(astNode, SamalSimpleListIsEmpty) != null) {
            var node = Std.downcast(astNode, SamalSimpleListIsEmpty);
            final nodeDatatype = addUsedDatatype(node.getDatatype().sure());
            var exprVarName = traverse(node.getList());
            var res = addStatement(new CppUnaryExprStatement(node.getSourceRef(), nodeDatatype, genTempVarName("list_is_empty"), exprVarName, ListIsEmpty));
            return res.getVarName();

        } else if(Std.downcast(astNode, SamalSimpleListGetHead) != null) {
            var node = Std.downcast(astNode, SamalSimpleListGetHead);
            final nodeDatatype = addUsedDatatype(node.getDatatype().sure());
            var exprVarName = traverse(node.getList());
            var res = addStatement(new CppUnaryExprStatement(node.getSourceRef(), nodeDatatype, genTempVarName("list_get_head"), exprVarName, ListGetHead));
            return res.getVarName();

        } else if(Std.downcast(astNode, SamalSimpleListGetTail) != null) {
            var node = Std.downcast(astNode, SamalSimpleListGetTail);
            final nodeDatatype = addUsedDatatype(node.getDatatype().sure());
            var exprVarName = traverse(node.getList());
            var res = addStatement(new CppUnaryExprStatement(node.getSourceRef(), nodeDatatype, genTempVarName("list_get_tail"), exprVarName, ListGetTail));
            return res.getVarName();

        } else if(Std.downcast(astNode, SamalLiteralIntExpression) != null) {
            var node = Std.downcast(astNode, SamalLiteralIntExpression);
            return mTarget.getLiteralInt(node.getVal());

        } else if(Std.downcast(astNode, SamalAssignmentExpression) != null) {
            var node = Std.downcast(astNode, SamalAssignmentExpression);
            final nodeDatatype = addUsedDatatype(node.getDatatype().sure());
            
            var rhsVarName = traverse(node.getRhs());

            addStatement(new CppAssignmentStatement(node.getSourceRef(), nodeDatatype, node.getIdentifier(), rhsVarName, CppAssignmentType.DeclareAndAssign));
            return node.getIdentifier();

        } else if(Std.downcast(astNode, SamalLoadIdentifierExpression) != null) {
            var node = Std.downcast(astNode, SamalLoadIdentifierExpression);
            return node.getIdentifier().mangled();
        } else if(Std.downcast(astNode, SamalFunctionCallExpression) != null) {
            var node = Std.downcast(astNode, SamalFunctionCallExpression);
            final nodeDatatype = addUsedDatatype(node.getDatatype().sure());
            var functionName = traverse(node.getFunction());

            var params = [];
            for(p in node.getParams()) {
                params.push(traverse(p));
            }
            var destName = genTempVarName("function_result");
            addStatement(new CppFunctionCallStatement(node.getSourceRef(), nodeDatatype, destName, functionName, params));

            return destName;
        
        } else if(Std.downcast(astNode, SamalSimpleIfExpression) != null) {
            var node = Std.downcast(astNode, SamalSimpleIfExpression);
            final nodeDatatype = addUsedDatatype(node.getDatatype().sure());

            final returnVarnmae = genTempVarName("if_result");
            var resultDeclaration = addStatement(new CppAssignmentStatement(node.getSourceRef(), nodeDatatype, returnVarnmae, "", CppAssignmentType.JustDeclare));

            var umbrellaScope = new CppScopeStatement(node.getSourceRef(), nodeDatatype, returnVarnmae);
            mScopeStack.add(umbrellaScope.getScope());

            var conditionVarName = traverse(node.getCondition());

            var mainScope = new CppScopeNode(node.getSourceRef());
            mScopeStack.add(mainScope);
            var lastStatementResult = "";
            for(stmt in node.getMainBody().getStatements()) {
                lastStatementResult = traverse(stmt);
            }
            if(lastStatementResult != "") {
                // if it's not after an unreachable point
                addStatement(new CppAssignmentStatement(node.getSourceRef(), nodeDatatype, returnVarnmae, lastStatementResult, CppAssignmentType.JustAssign));
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
                addStatement(new CppAssignmentStatement(node.getSourceRef(), nodeDatatype, returnVarnmae, lastStatementResult, CppAssignmentType.JustAssign));
            }
            mScopeStack.pop();

            addStatement(new CppIfStatement(node.getSourceRef(), nodeDatatype, returnVarnmae, conditionVarName, mainScope, elseScope));

            mScopeStack.pop();
            addStatement(umbrellaScope);
            
            return resultDeclaration.getVarName();

        } else if(Std.downcast(astNode, SamalSimpleListCreateEmpty) != null) {
            var node = Std.downcast(astNode, SamalSimpleListCreateEmpty);
            final nodeDatatype = addUsedDatatype(node.getDatatype().sure());
            return mTarget.getLiteralEmptyList();

        } else if(Std.downcast(astNode, SamalSimpleListPrepend) != null) {
            var node = Std.downcast(astNode, SamalSimpleListPrepend);
            final nodeDatatype = addUsedDatatype(node.getDatatype().sure());
            
            var valueVarName = traverse(node.getValue());
            var listVarName = traverse(node.getList());

            var varName = genTempVarName("list_prepend");
            addStatement(new CppListPrependStatement(node.getSourceRef(), nodeDatatype, varName, valueVarName, listVarName));
            return varName;

        } else if(Std.downcast(astNode, SamalSimpleUnreachable) != null) {
            addStatement(new CppUnreachable(astNode.getSourceRef()));
            return "";

        } else if(Std.downcast(astNode, SamalCreateLambdaExpression) != null) {
            var node = Std.downcast(astNode, SamalCreateLambdaExpression);
            final varName = genTempVarName("lambda");
            final functionDatatype = node.getDatatype().sure();

            // generate cpp body
            var scope = new CppScopeNode(node.getSourceRef());
            mScopeStack.add(scope);
            
            var lastStatementResult = "";
            for(stmt in node.getBody().getStatements()) {
                lastStatementResult = traverse(stmt);
            }
            if(lastStatementResult != "") {
                scope.addStatement(new CppReturnStatement(node.getSourceRef(), DatatypeHelpers.getReturnType(functionDatatype), lastStatementResult));
            }
            mScopeStack.pop();

            addStatement(new CppCreateLambdaStatement(node.getSourceRef(), functionDatatype, varName, node.getParameters(), node.getCapturedVariables(), scope));
            return varName;

        } else if(Std.downcast(astNode, SamalCreateStructExpression) != null) {
            var node = Std.downcast(astNode, SamalCreateStructExpression);
            final varName = genTempVarName("struct");

            final decl = Std.downcast(mSProgram.findDatatypeDeclaration(node.getDatatype().sure()), SamalStructDeclaration).sure();
            final params : Array<NamedAndValueStringedParameter> = [];
            for(expectedField in decl.getFields()) {
                // find passed param for field
                for(p in node.getParams()) {
                    if(p.getFieldName() != expectedField.getFieldName())
                        continue;
                    params.push({name : p.getFieldName(), value : traverse(p.getValue())});
                }
            }
            addStatement(new CppCreateStructStatement(node.getSourceRef(), node.getDatatype().sure(), varName, params));
            return varName;

        } else if(Std.downcast(astNode, SamalSimpleTailCallSelf) != null) {
            var node = Std.downcast(astNode, SamalSimpleTailCallSelf);
            var params : Array<TailCallSelfParam> = [];
            for(p in node.getParameters()) {
                params.push(new TailCallSelfParam(p.getParamName(), traverse(p.getValue())));
            }
            addStatement(new CppTailCallSelf(astNode.getSourceRef(), node.getDatatype().sure(), "", params));
            return "";

        } else {
            throw new Exception("TODO! " + Type.getClassName(Type.getClass(astNode)));
        }
        return "";
    }

    function samalToCppBody() {

    }

    public function convertToCppAST() : CppProgram {
        mCProgram = new CppProgram();
        
        mSProgram.forEachModule(function(moduleName : String, ast : SamalModule) {
            moduleName = Util.mangle(moduleName, []);
            mCurrentModuleName = moduleName;
            mCurrentFileDeclarations = [];
            mScopeStack = new GenericStack<CppScopeNode>();
            for(decl in ast.getDeclarations()) {
                traverse(decl);
            }
            mCProgram.addModule(moduleName, new CppFile(ast.getSourceRef(), moduleName, mCurrentFileDeclarations, mUsedDatatypes));
        });

        return mCProgram;
    }
}