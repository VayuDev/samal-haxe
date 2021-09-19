package samal.lang;

import samal.bootstrap.Tokenizer.SourceCodeRef;
import haxe.EnumTools;
import haxe.ds.GenericStack;
import haxe.Exception;
import samal.lang.Datatype.DatatypeHelpers;
import samal.lang.AST;
import samal.lang.generated.SamalAST;
import samal.lang.Util;
import samal.lang.Datatype;
using samal.lang.Util.NullTools;
using samal.lang.Datatype.DatatypeHelpers;
using samal.lang.Util.Util;
import samal.lang.Program;


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

class TemplateFunctionToCompile {
    var mFunctionDeclaration : SamalFunctionDeclaration;
    var mTypeMap : Map<String, Datatype>;
    var mPassedTemplateParams : Array<Datatype>;
    public function new(decl : SamalFunctionDeclaration, typeMap : Map<String, Datatype>, passedTemplateParams : Array<Datatype>) {
        mFunctionDeclaration = decl;
        mTypeMap = typeMap;
        mPassedTemplateParams = passedTemplateParams;
    }
    public function getFunctionDeclaration() {
        return mFunctionDeclaration;
    }
    public function getTypeMap() {
        return mTypeMap;
    }
    public function getPassedTemplateParams() {
        return mPassedTemplateParams;
    }
}

class Stage2 {
    var mProgram : SamalProgram;
    var mScopeStack : GenericStack<Map<String, VarDeclaration>> = new GenericStack();
    var mScopeStackLength = 0;
    var mCurrentModule : String = "";
    var mTempVarNameCounter : Int = 0;
    var mTemplateFunctionsToCompile : Map<String, TemplateFunctionToCompile> = new Map();
    var mCurrentTemplateReplacementMap = new Map<String, Datatype>();
    final mCompiledTemplateFunctions = new List<String>();
    var mCurrentFunction : Null<SamalFunctionDeclaration>;

    // Upon entering a lambda, this value is set to track which are variables are accessed in the body.
    // Afterwards, it is set back to null.
    var mOnStackedIdentifierLoadCallback : Null<(Int, String, Datatype) -> Void> = null;

    public function new(prog : SamalProgram) {
        mProgram = prog;
    }

    static function findDatatypeAndIndexOfEnumFieldFromEnumVariant(errorNode : ASTNode, fieldName : String, enumVariant : EnumDeclVariant) : {datatype: Datatype, index: Int} {
        for(index => declaredField in enumVariant.getFields()) {
            if(fieldName == declaredField.getFieldName()) {
                return {datatype: declaredField.getDatatype(), index: index};
            }
        }
        throw new Exception(errorNode.errorInfo() + " Can't find enum field " + fieldName + " in " + enumVariant.getFields());
        
    }

    function traverseMatchShape(astNode : SamalShape, toMatchDatatype : Datatype) : Void {
        // TODO check if match is exhaustive
        if(Std.downcast(astNode, SamalShapeEnumVariant) != null) {
            final node = Std.downcast(astNode, SamalShapeEnumVariant);
            if(!toMatchDatatype.match(Usertype(_, _, Enum))) {
                throw new Exception(node.errorInfo() + " Unable to match non-enum type as an enum variant: " + toMatchDatatype);
            }
            final typeDeclaration = mProgram.findDatatypeDeclaration(toMatchDatatype);
            final typeDeclAsEnumDecl = cast(typeDeclaration, SamalEnumDeclaration);
            final variant = Util.findEnumVariant(typeDeclAsEnumDecl.getVariants(), node.getVariant()).variant;
            
            for(usedField in node.getFields()) {
                traverseMatchShape(usedField.getValue(), findDatatypeAndIndexOfEnumFieldFromEnumVariant(node, usedField.getFieldName(), variant).datatype);
            }

        } else if(Std.downcast(astNode, SamalShapeSplitList) != null) {
            var node = Std.downcast(astNode, SamalShapeSplitList);
            if(!toMatchDatatype.match(List(_))) {
                throw new Exception(node.errorInfo() + " You can only split lists, not " + toMatchDatatype);
            }
            traverseMatchShape(node.getHead(), toMatchDatatype.getBaseType());
            traverseMatchShape(node.getTail(), toMatchDatatype);
        } else if(Std.downcast(astNode, SamalShapeVariable) != null) {
            var node = Std.downcast(astNode, SamalShapeVariable);
            if (mScopeStack.first().sure().exists(node.getVariableName())) {
                throw new Exception(node.errorInfo() + " Variable " + node.getVariableName() + " assigned twice.");
            }
            mScopeStack.first().sure().set(node.getVariableName(), new VarDeclaration(node.getVariableName(), toMatchDatatype));

        }
    }

    function pushStackFrame() {
        mScopeStack.add(new Map<String, VarDeclaration>());
        mScopeStackLength += 1;
    }
    function popStackFrame() {
        mScopeStack.pop();
        mScopeStackLength -= 1;
    }

    function traverse(astNode : ASTNode) : Void {
        if(Std.downcast(astNode, SamalScope) != null) {
            var node = Std.downcast(astNode, SamalScope);
            pushStackFrame();

            for(stmt in node.getStatements()) {
                traverse(stmt);
            }

            var stmt = node.getStatements();
            if(stmt.length == 0) {
                node.setDatatype(Datatype.Tuple([]));
            } else {
                node.setDatatype(stmt[stmt.length - 1].getDatatype().sure());
            }
            popStackFrame();

        } else if(Std.downcast(astNode, SamalScopeExpression) != null) {
            var node = Std.downcast(astNode, SamalScopeExpression);
            traverse(node.getScope());

        } else if(Std.downcast(astNode, SamalFunctionDeclaration) != null) {
            var node = Std.downcast(astNode, SamalFunctionDeclaration);
            mCurrentFunction = node;

            // function params
            pushStackFrame();
            for(param in node.getParams()) {
                mScopeStack.first().sure().set(param.getName(), new VarDeclaration(param.getName(), complete(param.getDatatype())));
            }
            traverse(node.getBody());

            // check return type
            final expectedReturnType = DatatypeHelpers.getReturnType(node.getDatatype());
            if(!expectedReturnType.deepEquals(node.getBody().getDatatype().sure())) {
                throw new Exception(
                    node.errorInfo() 
                    + "Expected return type " 
                    + expectedReturnType 
                    + ", got: " 
                    + node.getBody().getDatatype().sure());
            }
            popStackFrame();
        } else if(Std.downcast(astNode, SamalBinaryExpression) != null) {
            var node = Std.downcast(astNode, SamalBinaryExpression);
            traverse(node.getLhs());
            traverse(node.getRhs());
            final lhsType = node.getLhs().getDatatype().sure();
            final rhsType = node.getRhs().getDatatype().sure();

            if(!lhsType.deepEquals(rhsType)) {
                if(rhsType.match(List(_)) && lhsType.deepEquals(rhsType.getBaseType()) && node.getOp() == Add) {
                    // list prepend
                    node.setDatatype(rhsType);
                    return;
                }
                throw new Exception('${node.errorInfo()} Lhs and rhs types aren\'t equal. Lhs is ${node.getLhs().getDatatype().sure()}, rhs is ${node.getRhs().getDatatype().sure()}');
            }
            if(!([Int].contains(lhsType))) {
                throw new Exception('${node.errorInfo()} The ${node.getOp()} operator is only defined for integers, not for ${node.getLhs().getDatatype().sure()}');
            }
            if([Less, LessEqual, More, MoreEqual].contains(node.getOp())) {
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
            //trace(node.errorInfo() + ": " +  node.getIdentifier());
            try {
                var decl = findIdentifierForLoading(node.getIdentifier());
                node.setIdentifier(new IdentifierWithTemplate(decl.getIdentifier(), []));
                node.setDatatype(decl.getType());
            } catch(e) {
                throw new Exception('${node.errorInfo()} ${e.message}');
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
                    if(!returnType.deepEquals(branch.getBody().getDatatype().sure())) {
                        throw new Exception('${node.errorInfo()} All previous branches returned ${returnType}, but one returns ${branch.getBody().getDatatype().sure()}');
                    }
                }
                if(branch.getCondition().getDatatype().sure() != Datatype.Bool) {
                    throw new Exception('${branch.getCondition().errorInfo()} Condition must have bool-type, but has ${branch.getCondition().getDatatype().sure()}');
                }
            }
            if(!node.getElse().getDatatype().sure().deepEquals(returnType)) {
                throw new Exception('${node.errorInfo()} All previous branches returned ${returnType}, but the else returns ${node.getElse().getDatatype().sure()}');
            }
            node.setDatatype(returnType);

        } else if(Std.downcast(astNode, SamalCreateEnumExpression) != null) {
            final node = Std.downcast(astNode, SamalCreateEnumExpression);
            final enumDecl = cast(mProgram.findDatatypeDeclaration(node.getDatatype().sure()), SamalEnumDeclaration);
            final variant = Util.findEnumVariant(enumDecl.getVariants(), node.getVariantName()).variant;
            traverseAndVerifyCorrectUsertypeParams(node, node.getParams(), variant.getFields());

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
                        if(!baseType.sure().deepEquals(child.getDatatype().sure())) {
                            throw new Exception('${node.errorInfo()} Not all initial members have the same type; previous ones are ${baseType.sure()}, but one is ${child.getDatatype().sure()}');
                        }
                    }
                }
                node.setDatatype(Datatype.List(baseType.sure()));
            } else {
                node.setDatatype(complete(node.getDatatype().sure()));
            }
        } else if(Std.downcast(astNode, SamalMatchExpression) != null) {
            var node = Std.downcast(astNode, SamalMatchExpression);

            traverse(node.getToMatch());
            var toMatchDatatype = node.getToMatch().getDatatype().sure();
            var returnType : Null<Datatype> = null;
            for(row in node.getRows()) {
                pushStackFrame();
                traverseMatchShape(row.getShape(), toMatchDatatype);
                traverse(row.getBody());
                if(returnType == null) {
                    returnType = row.getBody().getDatatype().sure();
                } else {
                    if(!returnType.sure().deepEquals(row.getBody().getDatatype().sure())) {
                        // wrong row type
                        throw new Exception('${node.errorInfo()} All match-branches must have the same type; previous branches returned $returnType, but one returns ${row.getBody().getDatatype().sure()}');
                    }
                }
                popStackFrame();
            }
            node.setDatatype(returnType.sure());

        } else if(Std.downcast(astNode, SamalCreateLambdaExpression) != null) {
            var node = Std.downcast(astNode, SamalCreateLambdaExpression);

            node.setDatatype(complete(node.getDatatype().sure()));

            final startStackLength = mScopeStackLength;
            pushStackFrame();
            for(param in node.getParameters()) {
                mScopeStack.first().sure().set(param.getName(), new VarDeclaration(param.getName(), complete(param.getDatatype())));
            }
            // track all used variables, used in the C++-target for GC
            mOnStackedIdentifierLoadCallback = function(depth, name, datatype) {
                if(depth <= startStackLength) {
                    node.getCapturedVariables().push(NameAndTypeParam.create(name, datatype));
                }
            };
            traverse(node.getBody());
            mOnStackedIdentifierLoadCallback = null;
            if(!node.getBody().getDatatype().sure().deepEquals(node.getDatatype().sure().getReturnType())) {
                throw new Exception('${node.errorInfo()} Declared return type is ${node.getDatatype().sure().getReturnType()}, but actual type is ${node.getBody().getDatatype().sure()}');
            }
            popStackFrame();

        } else if(Std.downcast(astNode, SamalCreateStructExpression) != null) {
            var node = Std.downcast(astNode, SamalCreateStructExpression);
            node.setDatatype(complete(node.getDatatype().sure()));
            final decl = Std.downcast(mProgram.findDatatypeDeclaration(node.getDatatype().sure()), SamalStructDeclaration).sure();
            if(decl.getFields().length != node.getParams().length) {
                throw new Exception('${node.errorInfo()} Invalid number of parameters; struct expects ${decl.getFields().length} parameters, but you passed ${node.getParams().length}');
            }
            traverseAndVerifyCorrectUsertypeParams(node, node.getParams(), decl.getFields());

        } else if(Std.downcast(astNode, SamalTailCallSelf) != null) {
            var node = Std.downcast(astNode, SamalTailCallSelf);
            // check params
            final functionParams = mCurrentFunction.sure().getDatatype().getParams();
            if(node.getParameters().length != functionParams.length) {
                throw new Exception('${node.errorInfo()} Parameter length of tail call is wrong; expected ${functionParams.length}, but got ${node.getParameters().length}');
            }
            for(i in 0...functionParams.length) {
                traverse(node.getParameters()[i]);
                if(!node.getParameters()[i].getDatatype().sure().deepEquals(functionParams[i])) {
                    throw new Exception('${node.errorInfo()} Parameter at index ${i} is wrong; "
                        + "expected ${functionParams[i]}, but got ${node.getParameters()[i].getDatatype().sure()}');
                }
            }
            node.setDatatype(mCurrentFunction.sure().getDatatype().sure().getReturnType());
        }
    }

    function traverseAndVerifyCorrectUsertypeParams(node : ASTNode, params : Array<SamalCreateUsertypeParam>, expectedFields : Array<UsertypeField>) {
        for(param in params) {
            traverse(param.getValue());
            final actualType = param.getValue().getDatatype().sure();
            var found = false;
            for(field in expectedFields) {
                if(field.getFieldName() == param.getFieldName()) {
                    if(!actualType.deepEquals(field.getDatatype())) {
                        throw new Exception('${node.errorInfo()} Usertype param ${field.getFieldName()} has the wrong datatype; expected ${field.getDatatype()}, got ${actualType}');
                    }
                    found = true;
                }
            }
            if(!found) {
                throw new Exception('${node.errorInfo()} Usertype param ${param.getFieldName()} doesn\'t appear in the struct\'s declaration');
            }
        }
    }

    function complete(datatype : Datatype) : Datatype {
        return datatype.complete(new StringToDatatypeMapperUsingTypeMap(mCurrentTemplateReplacementMap));
    }

    function findIdentifierForLoading(name : IdentifierWithTemplate) : VarDeclaration {
        // search in local scope
        var remainingStackSize = mScopeStackLength;
        for(frame in mScopeStack) {
            var type = frame.get(name.getName());
            if(type != null) {
                // found the variable, call the callback and return
                if(mOnStackedIdentifierLoadCallback != null) {
                    mOnStackedIdentifierLoadCallback.sure()(remainingStackSize, type.getIdentifier(), type.getType());
                }
                return type;
            }
            remainingStackSize -= 1;
        }

        // search in global scope
        var func = mProgram.findFunction(name.getName(), mCurrentModule);
        // found a template function
        if(func.getTemplateParams().length > 0) {
            //try {
                final passedTemplateParams = name.getTemplateParams().map(function(p) return complete(p));
                final replacementMap = Util.buildTemplateReplacementMap(func.getTemplateParams(), passedTemplateParams);
                final completedFunctionType = func.getDatatype().complete(new StringToDatatypeMapperUsingTypeMap(replacementMap));
                final requiredMangledName = Util.mangle(func.getName().getName(), passedTemplateParams);
                if(!mTemplateFunctionsToCompile.exists(requiredMangledName)) {
                    mTemplateFunctionsToCompile.set(requiredMangledName, new TemplateFunctionToCompile(func, replacementMap, passedTemplateParams));
                }
                return new VarDeclaration(requiredMangledName, completedFunctionType);
            /*} catch(e : Exception) {
                throw new Exception("Error while instantiating " + name.dump() + ": " + e.toString());
            }*/
        }
        return new VarDeclaration(func.getName().mangled(), func.getDatatype());
    }

    function preorderReplace(astNode : ASTNode) : ASTNode {
        if(Std.downcast(astNode, SamalFunctionDeclaration) != null) {
            var node = Std.downcast(astNode, SamalFunctionDeclaration);
            mCurrentFunction = node;
            return node;
            
        } else if(Std.downcast(astNode, SamalIfExpression) != null) {
            var node = Std.downcast(astNode, SamalIfExpression);
            if(node.getElseIfs().length == 0) {
                return SamalSimpleIfExpression.createFull(node.getSourceRef(), node.getDatatype().sure(), node.getCondition(), node.getMainBody(), node.getElse());
            }
            var currentElseIf = node.getElseIfs().shift().sure();
            var reducedIfExpr = withDatatype(
                node.getDatatype().sure(), 
                SamalIfExpression.create(node.getSourceRef(), currentElseIf.getCondition(), currentElseIf.getBody(), node.getElseIfs(), node.getElse()));
            var newElseScope = SamalScope.create(node.getSourceRef(), [reducedIfExpr]);
            return SamalSimpleIfExpression.createFull(node.getSourceRef(), node.getDatatype().sure(), node.getCondition(), node.getMainBody(), newElseScope);

        } else if(Std.downcast(astNode, SamalCreateListExpression) != null) {
            var node = Std.downcast(astNode, SamalCreateListExpression);
            if(node.getChildren().length == 0) {
                return SamalSimpleListCreateEmpty.createFull(node.getSourceRef(), node.getDatatype().sure());
            }
            var currentChild = node.getChildren().shift().sure();
            return
                SamalSimpleListPrepend.createFull(
                    node.getSourceRef(),
                    node.getDatatype().sure(),
                    currentChild, 
                    SamalCreateListExpression.create(node.getSourceRef(), node.getChildren(), node.getDatatype().sure().getBaseType()));

        }  else if(Std.downcast(astNode, SamalBinaryExpression) != null) {
            var node = Std.downcast(astNode, SamalBinaryExpression);
            final lhsType = node.getLhs().getDatatype().sure();
            final rhsType = node.getRhs().getDatatype().sure();

            if(rhsType.match(List(_)) && lhsType.deepEquals(rhsType.getBaseType()) && node.getOp() == Add) {
                // list prepend
                return SamalSimpleListPrepend.createFull(node.getSourceRef(), rhsType, node.getLhs(), node.getRhs());
            }
        } else if(Std.downcast(astNode, SamalMatchExpression) != null) {
            var node = Std.downcast(astNode, SamalMatchExpression);

            var returnType = node.getDatatype().sure();
            var rootScope = SamalScope.create(node.getSourceRef(), []);
            var toMatchDatatype = node.getToMatch().getDatatype().sure();

            var toMatchVarName = genTempVarName("toMatch");
            rootScope.getStatements().push(SamalAssignmentExpression.createFull(node.getSourceRef(), toMatchDatatype, toMatchVarName, node.getToMatch()));

            // use separate scope so that it only contains the logic for matching each row
            final matchRootScope = SamalScope.create(node.getSourceRef(), []);
            rootScope.getStatements().push(SamalScopeExpression.createFull(node.getSourceRef(), returnType, matchRootScope));

            var ctx = new MatchShapeReplacementContext(matchRootScope);
            ctx.addElseAlongTheWay(matchRootScope); // just used for bootstrapping the first row

            for(row in node.getRows()) {
                final thisRowRoot = ctx.getLowestElse().sure();

                final lastCtx = ctx;
                ctx = new MatchShapeReplacementContext(thisRowRoot);
                replaceMatchShape(ctx, row.getShape(), toMatchVarName, toMatchDatatype, returnType);
                ctx.getCurrentBody().getStatements().push(row.getBody());

                // copy generated match code to all else-bodies in the prev run
                for(hangingElse in lastCtx.getElsesAlongTheWay()) {
                    if(hangingElse == thisRowRoot)
                        continue;
                    for(stmt in thisRowRoot.getStatements()) {
                        hangingElse.getStatements().push(stmt);
                    }
                }
            }

            // add unreachable for all other elses
            for(hangingElse in ctx.getElsesAlongTheWay()) {
                hangingElse.getStatements().push(SamalSimpleUnreachable.create(node.getSourceRef()));
            }

            return SamalScopeExpression.createFull(node.getSourceRef(), returnType, rootScope);
        } else if(Std.downcast(astNode, SamalTailCallSelf) != null) {
            var node = Std.downcast(astNode, SamalTailCallSelf);
            return SamalSimpleTailCallSelf.createFull(
                node.getSourceRef(), 
                node.getDatatype().sure(), 
                createTailCallSelfParamArray(
                    mCurrentFunction.sure().getParams().map(
                        function(p) return p.getName()), 
                    node.getParameters().map(
                        function(p) return cast(p.replace(preorderReplace, postorderReplace), SamalExpression)
                    )));
        }
        return astNode;
    }

    private static function createTailCallSelfParamArray(names : Array<String>, values : Array<SamalExpression>) : Array<SamalSimpleTailCallSelfParam> {
        if(names.length != values.length) {
            throw new Exception("Lengthes must match!");
        }
        var ret : Array<SamalSimpleTailCallSelfParam> = [];
        for(i in 0...names.length) {
            ret.push(SamalSimpleTailCallSelfParam.createFull(names[i], values[i]));
        }
        return ret;
    }

    function replaceMatchShape(ctx : MatchShapeReplacementContext, matchShape : SamalShape, currentVarName : String, currentVarDatatype : Datatype, returnType : Datatype) : Void {

        var loadCurrentVar = function() {
            return SamalLoadIdentifierExpression.createFull(matchShape.getSourceRef(), currentVarDatatype, new IdentifierWithTemplate(currentVarName, []));
        }

        var generateIfElse = function(check) {
            var checkSuccessBody = SamalScope.create(matchShape.getSourceRef(), []);
            checkSuccessBody.setDatatype(returnType);
            var checkElseBody = SamalScope.create(matchShape.getSourceRef(), []);
            checkElseBody.setDatatype(returnType);
            ctx.addElseAlongTheWay(checkElseBody);

            var ifExpr = SamalSimpleIfExpression.createFull(matchShape.getSourceRef(), returnType, check, checkSuccessBody, checkElseBody);
            ctx.getCurrentBody().getStatements().push(ifExpr);
            ctx.setCurrentBody(checkSuccessBody);

            return checkSuccessBody;
        }

        if(Std.downcast(matchShape, SamalShapeVariable) != null) {
            var node = Std.downcast(matchShape, SamalShapeVariable);
            var assignment = 
                    SamalAssignmentExpression.createFull(
                        node.getSourceRef(),
                        currentVarDatatype,
                        node.getVariableName(), 
                        loadCurrentVar());
            
            ctx.getCurrentBody().getStatements().push(assignment);

        } else if(Std.downcast(matchShape, SamalShapeEmptyList) != null) {
            var node = cast(matchShape, SamalShapeEmptyList);
            generateIfElse(SamalSimpleListIsEmpty.create(node.getSourceRef(), loadCurrentVar()));

        } else if(Std.downcast(matchShape, SamalShapeEnumVariant) != null) {
            final node = cast(matchShape, SamalShapeEnumVariant);
            final enumDecl = cast(mProgram.findDatatypeDeclaration(currentVarDatatype), SamalEnumDeclaration);
            final variantDecl = Util.findEnumVariant(enumDecl.getVariants(), node.getVariant());
            generateIfElse(SamalSimpleEnumIsVariant.createFull(
                node.getSourceRef(),
                Bool,
                loadCurrentVar(),
                node.getVariant(),
                variantDecl.index
            ));
            for(field in node.getFields()) {
                final declaredFieldInfo = findDatatypeAndIndexOfEnumFieldFromEnumVariant(node, field.getFieldName(), variantDecl.variant);
                final currentBody = ctx.getCurrentBody();
                final assignedFieldName = genTempVarName("enum_field");
                currentBody.getStatements().push(SamalAssignmentExpression.createFull(
                    node.getSourceRef(),
                    declaredFieldInfo.datatype,
                    assignedFieldName,
                    SamalSimpleFetchEnumField.createFull(
                        field.getValue().getSourceRef(), 
                        declaredFieldInfo.datatype, 
                        loadCurrentVar(), 
                        node.getVariant(), 
                        variantDecl.index,
                        field.getFieldName(),
                        declaredFieldInfo.index
                    )
                ));

                replaceMatchShape(ctx, field.getValue(), assignedFieldName, declaredFieldInfo.datatype, returnType);
            }

        } else if(Std.downcast(matchShape, SamalShapeSplitList) != null) {
            var node = Std.downcast(matchShape, SamalShapeSplitList);
            var checkSuccessBody = generateIfElse(
                SamalUnaryExpression.createFull(
                    node.getSourceRef(), 
                    Bool,
                    Not, 
                    SamalSimpleListIsEmpty.create(node.getSourceRef(), loadCurrentVar())));
            
            final headVarName = genTempVarName("listHead");
            checkSuccessBody.getStatements().push(
                SamalAssignmentExpression.createFull(
                    node.getSourceRef(), 
                    currentVarDatatype.getBaseType(), 
                    headVarName, 
                    SamalSimpleListGetHead.createFull(node.getSourceRef(), currentVarDatatype.getBaseType(), loadCurrentVar())));
            
            final tailVarName = genTempVarName("listTail");
            checkSuccessBody.getStatements().push(
                SamalAssignmentExpression.createFull(
                    node.getSourceRef(), 
                    currentVarDatatype,
                    tailVarName, 
                    SamalSimpleListGetTail.createFull(node.getSourceRef(), currentVarDatatype, loadCurrentVar())));

            replaceMatchShape(ctx, node.getHead(), headVarName, currentVarDatatype.getBaseType(), returnType);
            replaceMatchShape(ctx, node.getTail(), tailVarName, currentVarDatatype, returnType);

        } else {
            throw new Exception("TODO");
        }
    }

    function postorderReplace(astNode : ASTNode) : ASTNode {
        return astNode;
    }

    function genTempVarName(baseName : String) : String {
        mTempVarNameCounter += 1;
        return baseName + "$$" + mTempVarNameCounter;
    }

    static function withDatatype(datatype : Datatype, node : SamalExpression) : SamalExpression {
        node.setDatatype(datatype);
        return node;
    }

    public function completeDatatypes() : SamalProgram {
        mProgram.forEachModule(function (moduleName : String, ast : SamalModule) {
            mCurrentModule = moduleName;
            // traverse all normal functions
            final pureTemplateDeclarations = new List<SamalDeclaration>();
            for(decl in ast.getDeclarations()) {
                if(Std.downcast(decl, SamalFunctionDeclaration) == null)
                    continue;
                if(decl.getTemplateParams().length == 0) {
                    traverse(decl);
                } else {
                    // it's a pure template function
                    pureTemplateDeclarations.add(decl);
                }
            }
            trace("Instantiating template functions!");
            // instantiate used template functions
            var it = mTemplateFunctionsToCompile.keyValueIterator();
            while(it.hasNext()) {
                final current = it.next();
                
                mCurrentTemplateReplacementMap = current.value.getTypeMap();
                final decl = current.value.getFunctionDeclaration().cloneWithTemplateParams(
                    new StringToDatatypeMapperUsingTypeMap(current.value.getTypeMap()), current.value.getPassedTemplateParams());
                trace(decl.getDatatype());
                traverse(decl);
                ast.getDeclarations().push(decl);
                mTemplateFunctionsToCompile.remove(current.key);
                it = mTemplateFunctionsToCompile.keyValueIterator();
                mCompiledTemplateFunctions.add(current.key);
            }

            // delete pure template functions
            for(pureDecl in pureTemplateDeclarations) {
                ast.getDeclarations().remove(pureDecl);
            }
            // simplify AST
            ast.replace(preorderReplace, postorderReplace);
        });
        return mProgram;
    }
}