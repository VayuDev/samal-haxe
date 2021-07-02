package samal;

import haxe.EnumTools;
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

class MatchShapeReplacementContext {
    var mCurrentBody : SamalScope;
    var mElsesAlongTheWay : Array<SamalScope> = [];

    public function new(currentBody : SamalScope) {
        mCurrentBody = currentBody;
    }
    public function setCurrentBody(body : SamalScope) {
        mCurrentBody = body;
    }
    public function getCurrentBody() {
        return mCurrentBody;
    }
    public function getLowestElse() {
        return mElsesAlongTheWay[mElsesAlongTheWay.length - 1];
    }
    public function getElsesAlongTheWay() {
        return mElsesAlongTheWay;
    }
    public function addElseAlongTheWay(elseBody : SamalScope) {
        mElsesAlongTheWay.push(elseBody);
    }
}

class Stage2 {
    var mProgram : SamalProgram;
    var mScopeStack : GenericStack<Map<String, VarDeclaration>> = new GenericStack();
    var mCurrentModule : String = "";
    var mTempVarNameCounter : Int = 0;

    public function new(prog : SamalProgram) {
        mProgram = prog;
    }

    function traverseMatchShape(astNode : SamalShape, toMatchDatatype : Datatype) {
        // TODO check if match is exhaustive
        if(Std.downcast(astNode, SamalShapeVariable) != null) {
            var node = Std.downcast(astNode, SamalShapeVariable);
            if (mScopeStack.first().sure().exists(node.getVariableName())) {
                throw new Exception(node.errorInfo() + " Variable " + node.getVariableName() + " assigned twice.");
            }
            mScopeStack.first().sure().set(node.getVariableName(), new VarDeclaration(node.getVariableName(), toMatchDatatype));
        } else if(Std.downcast(astNode, SamalShapeSplitList) != null) {
            var node = Std.downcast(astNode, SamalShapeSplitList);
            if(!toMatchDatatype.match(List(_))) {
                throw new Exception(node.errorInfo() + " You can only split lists, not " + toMatchDatatype);
            }
            traverseMatchShape(node.getHead(), toMatchDatatype.getBaseType());
            traverseMatchShape(node.getTail(), toMatchDatatype);
        }
    }

    function traverse(astNode : ASTNode) {
        if(Std.downcast(astNode, SamalModuleNode) != null) {
            var node = Std.downcast(astNode, SamalModuleNode);
            for(decl in node.getDeclarations()) {
                traverse(decl);
            }    
            
        } else if(Std.downcast(astNode, SamalScope) != null) {
            var node = Std.downcast(astNode, SamalScope);
            mScopeStack.add(new Map<String, VarDeclaration>());

            for(stmt in node.getStatements()) {
                traverse(stmt);
            }

            var stmt = node.getStatements();
            if(stmt.length == 0) {
                node.setDatatype(Datatype.Tuple([]));
            } else {
                node.setDatatype(stmt[stmt.length - 1].getDatatype().sure());
            }
            mScopeStack.pop();

        } else if(Std.downcast(astNode, SamalScopeExpression) != null) {
            var node = Std.downcast(astNode, SamalScopeExpression);
            traverse(node.getScope());

        } else if(Std.downcast(astNode, SamalFunctionDeclarationNode) != null) {
            var node = Std.downcast(astNode, SamalFunctionDeclarationNode);

            // function params
            mScopeStack.add(new Map<String, VarDeclaration>());
            for(param in node.getParams()) {
                mScopeStack.first().sure().set(param.getName(), new VarDeclaration(param.getName(), param.getDatatype()));
            }
            traverse(node.getBody());

            // check return type
            final expectedReturnType = DatatypeHelpers.getReturnType(node.getDatatype());
            if(!expectedReturnType.equals(node.getBody().getDatatype().sure())) {
                throw new Exception(
                    node.errorInfo() 
                    + "Expected return type " 
                    + expectedReturnType 
                    + ", got: " 
                    + node.getBody().getDatatype().sure());
            }
            mScopeStack.pop();
        } else if(Std.downcast(astNode, SamalBinaryExpression) != null) {
            var node = Std.downcast(astNode, SamalBinaryExpression);
            traverse(node.getLhs());
            traverse(node.getRhs());
            final lhsType = node.getLhs().getDatatype().sure();
            final rhsType = node.getRhs().getDatatype().sure();

            if(!lhsType.equals(rhsType)) {
                if(rhsType.match(List(_)) && lhsType.equals(rhsType.getBaseType()) && node.getOperator() == Add) {
                    // list prepend
                    node.setDatatype(rhsType);
                    return;
                }
                throw new Exception('${node.errorInfo()} Lhs and rhs types aren\'t equal. Lhs is ${node.getLhs().getDatatype().sure()}, rhs is ${node.getRhs().getDatatype().sure()}');
            }
            if(!([Int].contains(lhsType))) {
                throw new Exception('${node.errorInfo()} The ${node.getOperator()} operator is only defined for integers, not for ${node.getLhs().getDatatype().sure()}');
            }
            if([Less, LessEqual, More, MoreEqual].contains(node.getOperator())) {
                node.setDatatype(Datatype.Bool);
            } else {
                node.setDatatype(lhsType);
            }

        } else if(Std.downcast(astNode, SamalAssignmentExpression) != null) {
            var node = Std.downcast(astNode, SamalAssignmentExpression);
            traverse(node.getRhs());

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
            traverse(node.getFunction());
            for(param in node.getParams()) {
                traverse(param);
            }
            node.setDatatype(node.getFunction().getDatatype().sure().getReturnType());

        } else if(Std.downcast(astNode, SamalIfExpression) != null) {
            var node = Std.downcast(astNode, SamalIfExpression);
            for(branch in node.getAllBranches()) {
                traverse(branch.getCondition());
                traverse(branch.getBody());
            }
            traverse(node.getElse());

            var returnType : Null<Datatype> = null;
            for(branch in node.getAllBranches()) {
                if(returnType == null) {
                    returnType = branch.getBody().getDatatype().sure();
                } else {
                    if(returnType != branch.getBody().getDatatype().sure()) {
                        throw new Exception('${node.errorInfo()} All previous branches returend ${returnType}, but one returns ${branch.getBody().getDatatype().sure()}');
                    }
                }
                if(branch.getCondition().getDatatype().sure() != Datatype.Bool) {
                    throw new Exception('${branch.getCondition().errorInfo()} Condition must have bool-type, but has ${branch.getCondition().getDatatype().sure()}');
                }
            }
            if(node.getElse().getDatatype().sure() != returnType) {
                throw new Exception('${node.errorInfo()} All previous branches returend ${returnType}, but the else returns ${node.getElse().getDatatype().sure()}');
            }
            node.setDatatype(returnType);
        } else if(Std.downcast(astNode, SamalCreateListExpression) != null) {
            var node = Std.downcast(astNode, SamalCreateListExpression);
            for(child in node.getChildren()) {
                traverse(child);
            }
            if(node.getDatatype() == null) {
                var baseType : Null<Datatype> = null;
                for(child in node.getChildren()) {
                    if(baseType == null) {
                        baseType = child.getDatatype();
                    } else {
                        if(!baseType.sure().equals(child.getDatatype().sure())) {
                            throw new Exception('${node.errorInfo()} Not all initial members have the same type; previous ones are ${baseType.sure()}, but one is ${child.getDatatype().sure()}');
                        }
                    }
                }
                node.setDatatype(Datatype.List(baseType.sure()));
            }
        } else if(Std.downcast(astNode, SamalMatchExpression) != null) {
            var node = Std.downcast(astNode, SamalMatchExpression);

            traverse(node.getToMatch());
            var toMatchDatatype = node.getToMatch().getDatatype().sure();
            var returnType : Null<Datatype> = null;
            for(row in node.getRows()) {
                mScopeStack.add(new Map<String, VarDeclaration>());
                traverseMatchShape(row.getShape(), toMatchDatatype);
                traverse(row.getBody());
                if(returnType == null) {
                    returnType = row.getBody().getDatatype().sure();
                } else {
                    if(!returnType.sure().equals(row.getBody().getDatatype().sure())) {
                        // wrong row type
                        throw new Exception('${node.errorInfo()} All match-branches must have the same type; previous branches returned $returnType, but one returns ${row.getBody().getDatatype().sure()}');
                    }
                }
                mScopeStack.pop();
            }
            node.setDatatype(returnType.sure());
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

    function preorderReplace(astNode : ASTNode) : ASTNode {
        if(Std.downcast(astNode, SamalIfExpression) != null) {
            var node = Std.downcast(astNode, SamalIfExpression);
            if(node.getElseIfs().length == 0) {
                return withDatatype(node.getDatatype().sure(), new SamalSimpleIfExpression(node.getSourceRef(), node.getMainCondition(), node.getMainBody(), node.getElse()));
            }
            var currentElseIf = node.getElseIfs().shift().sure();
            var reducedIfExpr = withDatatype(
                node.getDatatype().sure(), 
                new SamalIfExpression(node.getSourceRef(), currentElseIf.getCondition(), currentElseIf.getBody(), node.getElseIfs(), node.getElse()));
            var newElseScope = new SamalScope(node.getSourceRef(), [reducedIfExpr]);
            return withDatatype(node.getDatatype().sure(), new SamalSimpleIfExpression(node.getSourceRef(), node.getMainCondition(), node.getMainBody(), newElseScope));

        } else if(Std.downcast(astNode, SamalCreateListExpression) != null) {
            var node = Std.downcast(astNode, SamalCreateListExpression);
            if(node.getChildren().length == 0) {
                return new SamalSimpleCreateEmptyList(node.getSourceRef(), node.getDatatype().sure());
            }
            var currentChild = node.getChildren().shift().sure();
            return withDatatype(
                node.getDatatype().sure(),
                new SamalSimpleListPrepend(
                    node.getSourceRef(), 
                    node.getDatatype().sure(), 
                    currentChild, 
                    new SamalCreateListExpression(node.getSourceRef(), node.getDatatype().sure().getBaseType(), node.getChildren())));

        } else if(Std.downcast(astNode, SamalBinaryExpression) != null) {
            var node = Std.downcast(astNode, SamalBinaryExpression);
            final lhsType = node.getLhs().getDatatype().sure();
            final rhsType = node.getRhs().getDatatype().sure();

            if(rhsType.match(List(_)) && lhsType.equals(rhsType.getBaseType()) && node.getOperator() == Add) {
                // list prepend
                return new SamalSimpleListPrepend(node.getSourceRef(), rhsType, node.getLhs(), node.getRhs());
            }
        } else if(Std.downcast(astNode, SamalMatchExpression) != null) {
            var node = Std.downcast(astNode, SamalMatchExpression);

            var returnType = node.getDatatype().sure();
            var rootScope = new SamalScope(node.getSourceRef(), []);
            var toMatchDatatype = node.getToMatch().getDatatype().sure();

            var toMatchVarName = genTempVarName("toMatch");
            rootScope.addStatement(withDatatype(toMatchDatatype, new SamalAssignmentExpression(node.getSourceRef(), toMatchVarName, node.getToMatch())));

            // use separate scope so that it only contains the logic for matching each row
            final matchRootScope = new SamalScope(node.getSourceRef(), []);
            rootScope.addStatement(withDatatype(returnType, new SamalScopeExpression(node.getSourceRef(), matchRootScope)));

            var ctx = new MatchShapeReplacementContext(matchRootScope);
            ctx.addElseAlongTheWay(matchRootScope); // just used for bootstrapping the first row

            for(row in node.getRows()) {
                final thisRowRoot = ctx.getLowestElse().sure();

                final lastCtx = ctx;
                ctx = new MatchShapeReplacementContext(thisRowRoot);
                replaceMatchShape(ctx, row.getShape(), toMatchVarName, toMatchDatatype, returnType);
                ctx.getCurrentBody().addStatement(row.getBody());

                // copy generated match code to all else-bodies in the prev run
                for(hangingElse in lastCtx.getElsesAlongTheWay()) {
                    if(hangingElse == thisRowRoot)
                        continue;
                    for(stmt in thisRowRoot.getStatements()) {
                        hangingElse.addStatement(stmt);
                    }
                }
            }

            // add unreachable for all other elses
            for(hangingElse in ctx.getElsesAlongTheWay()) {
                hangingElse.addStatement(new SamalSimpleUnreachable(node.getSourceRef()));
            }

            return withDatatype(returnType, new SamalScopeExpression(node.getSourceRef(), rootScope));
        }
        return astNode;
    }

    function replaceMatchShape(ctx : MatchShapeReplacementContext, matchShape : SamalShape, currentVarName : String, currentVarDatatype : Datatype, returnType : Datatype) {

        var loadCurrentVar = function() {
            return withDatatype(
                currentVarDatatype,
                new SamalLoadIdentifierExpression(matchShape.getSourceRef(), new IdentifierWithTemplate(currentVarName, [])));
        }

        var generateIfElse = function(check) {
            var checkSuccessBody = new SamalScope(matchShape.getSourceRef(), []);
            checkSuccessBody.setDatatype(returnType);
            var checkElseBody = new SamalScope(matchShape.getSourceRef(), []);
            checkElseBody.setDatatype(returnType);
            ctx.addElseAlongTheWay(checkElseBody);

            var ifExpr = withDatatype(returnType, new SamalSimpleIfExpression(matchShape.getSourceRef(), check, checkSuccessBody, checkElseBody));
            ctx.getCurrentBody().addStatement(ifExpr);
            ctx.setCurrentBody(checkSuccessBody);

            return checkSuccessBody;
        }

        if(Std.downcast(matchShape, SamalShapeVariable) != null) {
            var node = Std.downcast(matchShape, SamalShapeVariable);
            var assignment = 
                withDatatype(
                    currentVarDatatype, 
                    new SamalAssignmentExpression(
                        node.getSourceRef(), 
                        node.getVariableName(), 
                        loadCurrentVar()));
            
            ctx.getCurrentBody().addStatement(assignment);
        } else if(Std.downcast(matchShape, SamalShapeEmptyList) != null) {
            var node = Std.downcast(matchShape, SamalShapeEmptyList);
            generateIfElse(new SamalSimpleListIsEmpty(node.getSourceRef(), loadCurrentVar()));
            

        } else if(Std.downcast(matchShape, SamalShapeSplitList) != null) {
            var node = Std.downcast(matchShape, SamalShapeSplitList);
            var checkSuccessBody = generateIfElse(withDatatype(
                Bool, 
                new SamalUnaryExpression(
                    node.getSourceRef(), 
                    Not, 
                    new SamalSimpleListIsEmpty(node.getSourceRef(), loadCurrentVar()))));
            
            final headVarName = genTempVarName("listHead");
            checkSuccessBody.addStatement(withDatatype(
                currentVarDatatype.getBaseType(), 
                new SamalAssignmentExpression(
                    node.getSourceRef(), 
                    headVarName, 
                    new SamalSimpleListGetHead(node.getSourceRef(), currentVarDatatype, loadCurrentVar()))));
            
            final tailVarName = genTempVarName("listTail");
            checkSuccessBody.addStatement(withDatatype(
                currentVarDatatype, 
                new SamalAssignmentExpression(
                    node.getSourceRef(), 
                    tailVarName, 
                    new SamalSimpleListGetTail(node.getSourceRef(), currentVarDatatype, loadCurrentVar()))));

            replaceMatchShape(ctx, node.getHead(), headVarName, currentVarDatatype.getBaseType(), returnType);
            replaceMatchShape(ctx, node.getTail(), tailVarName, currentVarDatatype, returnType);

        } else {
            throw new Exception("TODO");
        }
    }

    function postorderReplace(astNode : ASTNode) : ASTNode {
        return astNode;
    }

    function genTempVarName(baseName : String) {
        mTempVarNameCounter += 1;
        return baseName + "$$" + mTempVarNameCounter;
    }

    static function withDatatype(datatype : Datatype, node : SamalExpression) : SamalExpression {
        node.setDatatype(datatype);
        return node;
    }

    public function completeDatatypes() : SamalProgram {
        mProgram.forEachModule(function (moduleName : String, ast : ASTNode) {
            mCurrentModule = moduleName;
            traverse(ast);
            ast.replace(preorderReplace, postorderReplace);
        });
        return mProgram;
    }
}