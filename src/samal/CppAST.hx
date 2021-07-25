package samal;

import samal.AST;
import samal.Tokenizer.SourceCodeRef;

using samal.Datatype.DatatypeHelpers;
using samal.Util.NullTools;
import samal.targets.LanguageTarget;


class CppASTNode extends ASTNode {
    public function new(sourceRef : SourceCodeRef) {
        super(sourceRef);
    }

    public function toSrc(target : LanguageTarget, ctx : SourceCreationContext) : String {
        return target.makeDefault(ctx, this);
    }
    function indent(ctx : SourceCreationContext) : String {
        return Util.createIndentStr(ctx.getIndent());
    }
}
class CppFile extends CppASTNode {
    var mDeclarations : Array<CppDeclaration>;
    var mName : String;
    final mUsedDatatypes : Array<Datatype>;
    public function new(sourceRef : SourceCodeRef, name : String, declarations : Array<CppDeclaration>, usedDatatypes : Array<Datatype>) {
        super(sourceRef);
        mDeclarations = declarations;
        mName = name;
        mUsedDatatypes = usedDatatypes;
    }
    public override function replaceChildren(preorder : (ASTNode) -> ASTNode, postorder : (ASTNode) -> ASTNode) {
        mDeclarations = Util.replaceNodes(mDeclarations, preorder, postorder);
    }
    public override function toSrc(target : LanguageTarget, ctx : SourceCreationContext) {
        return target.makeFile(ctx, this);
    }
    public function getName() {
        return mName;
    }
    public function getDeclarations() {
        return mDeclarations;
    }
    public function getUsedDatatypes() {
        return mUsedDatatypes;
    }
}

class CppScopeNode extends CppASTNode {
    var mStatements : Array<CppStatement> = [];
    public function addStatement(stmt : CppStatement) {
        mStatements.push(stmt);
    }
    public override function replaceChildren(preorder : (ASTNode) -> ASTNode, postorder : (ASTNode) -> ASTNode) {
        mStatements = Util.replaceNodes(mStatements, preorder, postorder);
    }
    public function isStatementsEmpty() : Bool {
        return mStatements.length == 0;
    }
    public function getLastStatement() : CppStatement {
        return mStatements[mStatements.length - 1];
    }
    public override function toSrc(target : LanguageTarget, ctx : SourceCreationContext) {
        return target.makeScopeNode(ctx, this);
    }
    public function getStatements() {
        return mStatements;
    }
}

class CppDeclaration extends CppASTNode {

}

class CppFunctionDeclaration extends CppDeclaration {
    var mDatatype : Datatype;
    var mMangledName : String;
    var mParams : Array<NamedAndTypedParameter>;
    var mBody : CppScopeNode;
    public function new(sourceRef : SourceCodeRef, datatype : Datatype, mangledName : String, params : Array<NamedAndTypedParameter>, body : CppScopeNode) {
        super(sourceRef);
        mDatatype = datatype;
        mMangledName = mangledName;
        mParams = params;
        mBody = body;
    }
    public override function replaceChildren(preorder : (ASTNode) -> ASTNode, postorder : (ASTNode) -> ASTNode) {
        mBody = cast(mBody.replace(preorder, postorder), CppScopeNode);
    }
    public override function toSrc(target : LanguageTarget, ctx : SourceCreationContext) {
        return target.makeFunctionDeclaration(ctx, this);
    }
    public function getParams() {
        return mParams;
    }
    public function getDatatype() {
        return mDatatype;
    }
    public function getMangledName() {
        return mMangledName;
    }
    public function getBody() {
        return mBody;
    }
}

class CppStructDeclaration extends CppDeclaration {
    var mDatatype : Datatype;
    var mMangledName : String;
    var mFields : Array<StructField>;
    public function new(sourceRef : SourceCodeRef, datatype : Datatype, mangledName : String, fields : Array<StructField>) {
        super(sourceRef);
        mDatatype = datatype;
        mMangledName = mangledName;
        mFields = fields;
    }
    public override function toSrc(target : LanguageTarget, ctx : SourceCreationContext) {
        return target.makeStructDeclaration(ctx, this);
    }
    public function getFields() {
        return mFields;
    }
    public function getDatatype() {
        return mDatatype;
    }
    public function getMangledName() {
        return mMangledName;
    }
}

abstract class CppStatement extends CppASTNode {
    var mVarName : String;
    var mDatatype : Datatype;
    public function new(sourceRef : SourceCodeRef, datatype: Datatype, varName : String) {
        super(sourceRef);
        mVarName = varName;
        mDatatype = datatype;
    }
    public function getVarName() {
        return mVarName;
    }
    public function getDatatype() {
        return mDatatype;
    }
}

class CppScopeStatement extends CppStatement {
    var mScope : CppScopeNode;
    public function new(sourceRef : SourceCodeRef, datatype : Datatype, varName : String, scope : Null<CppScopeNode> = null) {
        super(sourceRef, datatype, varName);
        if(scope != null) {
            mScope = scope.sure();
        } else {
            mScope = new CppScopeNode(sourceRef);
        }
    }
    public function getScope() {
        return mScope;
    }
    public override function replaceChildren(preorder : (ASTNode) -> ASTNode, postorder : (ASTNode) -> ASTNode) {
        mScope = cast(mScope.replace(preorder, postorder), CppScopeNode);
    }
    public override function toSrc(target : LanguageTarget, ctx : SourceCreationContext) {
        return target.makeScopeStatement(ctx, this);
    }
}

enum CppBinaryExprOp {
    Add;
    Sub;
    Mul;
    Div;
    Less;
    More;
    LessEqual;
    MoreEqual;
}

class CppBinaryExprStatement extends CppStatement {
    var mLhsVarName : String;
    var mRhsVarName : String;
    var mOp : CppBinaryExprOp;
    public function new(sourceRef : SourceCodeRef, datatype : Datatype, resultVarName : String, lhsVarName : String, op : CppBinaryExprOp, rhsVarName : String) {
        super(sourceRef, datatype, resultVarName);
        mLhsVarName = lhsVarName;
        mRhsVarName = rhsVarName;
        mOp = op;
    }
    public override function dumpSelf() : String {
        return super.dumpSelf() + ": " + mVarName + " = " + mLhsVarName + " " + mOp + " " + mRhsVarName;
    }
    public function opAsStr() : String {
        switch(mOp) {
            case Add:
                return "+";
            case Sub:
                return "-";
            case Mul:
                return "*";
            case Div:
                return "/";
            case Less:
                return "<";
            case More:
                return ">";
            case LessEqual:
                return "<=";
            case MoreEqual:
                return ">=";
        }
    }
    public override function toSrc(target : LanguageTarget, ctx : SourceCreationContext) {
        return target.makeBinaryExprStatement(ctx, this);
    }
    public function getLhsVarName() {
        return mLhsVarName;
    }
    public function getRhsVarName() {
        return mRhsVarName;
    }
}

enum CppUnaryOp {
    Not;
    ListGetHead;
    ListGetTail;
    ListIsEmpty;
}

class CppUnaryExprStatement extends CppStatement {
    var mExpr : String;
    var mOp : CppUnaryOp;
    public function new(sourceRef : SourceCodeRef, datatype : Datatype, resultVarName : String, expr : String, op : CppUnaryOp) {
        super(sourceRef, datatype, resultVarName);
        mExpr = expr;
        mOp = op;
    }
    public override function dumpSelf() : String {
        return super.dumpSelf() + ": " + mVarName + " = " +  mOp + " " + mExpr;
    }
    public override function toSrc(target : LanguageTarget, ctx : SourceCreationContext) {
        return target.makeUnaryExprStatement(ctx, this);
    }
    public function getOp() {
        return mOp;
    }
    public function getExpr() {
        return mExpr;
    }
}

class CppUnreachable extends CppStatement {
    public function new(sourceRef : SourceCodeRef) {
        super(sourceRef, Datatype.Bool, "");
    }
    public override function toSrc(target : LanguageTarget, ctx : SourceCreationContext) {
        return target.makeUnreachable(ctx, this);
    }
}

enum CppAssignmentType {
    JustDeclare;
    JustAssign;
    DeclareAndAssign;
}

class CppAssignmentStatement extends CppStatement {
    var mRhsVarName : String;
    var mType : CppAssignmentType;
    public function new(sourceRef : SourceCodeRef, datatype : Datatype, resultVarName : String, rhsVarName : String, type : CppAssignmentType) {
        super(sourceRef, datatype, resultVarName);
        mRhsVarName = rhsVarName;
        mType = type;
    }
    public override function dumpSelf() : String {
        return super.dumpSelf() + ": " + mVarName + " = " + mRhsVarName + " (" + mType + ")";
    }
    public override function toSrc(target : LanguageTarget, ctx : SourceCreationContext) {
        return target.makeAssignmentStatement(ctx, this);
    }
    public function getType() {
        return mType;
    }
    public function getRhsVarName() {
        return mRhsVarName;
    }
}

class CppReturnStatement extends CppStatement {
    public function new(sourceRef : SourceCodeRef, datatype : Datatype, varName : String) {
        super(sourceRef, datatype, varName);
    }
    public override function dumpSelf() : String {
        return super.dumpSelf() + ": " + mVarName;
    }
    public override function toSrc(target : LanguageTarget, ctx : SourceCreationContext) {
        return target.makeReturnStatement(ctx, this);
    }
}

class CppFunctionCallStatement extends CppStatement {
    var mFunctionName : String;
    var mParams : Array<String>;
    public function new(sourceRef : SourceCodeRef, datatype : Datatype, varName : String, functionName : String, params : Array<String>) {
        super(sourceRef, datatype, varName);
        mFunctionName = functionName;
        mParams = params;
    }
    public override function dumpSelf() : String {
        return super.dumpSelf() + ": " + mVarName;
    }
    public override function toSrc(target : LanguageTarget, ctx : SourceCreationContext) {
        return target.makeFunctionCallStatement(ctx, this);
    }
    public function getFunctionName() {
        return mFunctionName;
    }
    public function getParams() {
        return mParams;
    }
}

class CppIfStatement extends CppStatement {
    var mConditionVarName : String;
    var mMainBody : CppScopeNode;
    var mElseBody : CppScopeNode;
    public function new(sourceRef : SourceCodeRef, datatype : Datatype, varName : String, conditionVarName : String, mainBody : CppScopeNode, elseBody : CppScopeNode) {
        super(sourceRef, datatype, varName);
        mConditionVarName = conditionVarName;
        mMainBody = mainBody;
        mElseBody = elseBody;
    }
    public override function dumpSelf() : String {
        return super.dumpSelf() + ": " + mVarName;
    }
    public override function toSrc(target : LanguageTarget, ctx : SourceCreationContext) {
        return target.makeIfStatement(ctx, this);
    }
    public override function replaceChildren(preorder : (ASTNode) -> ASTNode, postorder : (ASTNode) -> ASTNode) {
        mMainBody = cast(mMainBody.replace(preorder, postorder), CppScopeNode);
        mElseBody = cast(mElseBody.replace(preorder, postorder), CppScopeNode);
    }
    public function getConditionVarName() {
        return mConditionVarName;
    }
    public function getMainBody() {
        return mMainBody;
    }
    public function getElseBody() {
        return mElseBody;
    }
}

class CppListPrependStatement extends CppStatement {
    var mValue : String;
    var mList : String;

    public function new(sourceRef : SourceCodeRef, datatype : Datatype, varName : String, value : String, list : String) {
        super(sourceRef, datatype, varName);
        mValue = value;
        mList = list;
    }

    public override function toSrc(target : LanguageTarget, ctx : SourceCreationContext) {
        return target.makeListPrependStatement(ctx, this);
    }
    public function getValue() {
        return mValue;
    }
    public function getList() {
        return mList;
    }
}

class CppCreateLambdaStatement extends CppStatement {
    final mParams : Array<NamedAndTypedParameter>;
    final mCapturedVariables : Array<NamedAndTypedParameter>;
    final mBody : CppScopeNode;

    public function new(sourceRef : SourceCodeRef, datatype : Datatype, varName : String, 
                        params : Array<NamedAndTypedParameter>, capturedVariables : Array<NamedAndTypedParameter>, body : CppScopeNode) {
        super(sourceRef, datatype, varName);
        mParams = params;
        mCapturedVariables = capturedVariables;
        mBody = body;
    }

    public override function toSrc(target : LanguageTarget, ctx : SourceCreationContext) {
        return target.makeCreateLambdaStatement(ctx, this);
    }
    public function getParams() {
        return mParams;
    }
    public function getCapturedVariables() {
        return mCapturedVariables;
    }
    public function getBody() {
        return mBody;
    }
}

class TailCallSelfParam {
    public var paramName(default,null) : String;
    public var paramValue(default, null) : String;
    public function new(paramName : String, paramValue : String) {
        this.paramName = paramName;
        this.paramValue = paramValue;
    }
}

class CppTailCallSelf extends CppStatement {
    final mParams : Array<TailCallSelfParam>;

    public function new(sourceRef : SourceCodeRef, datatype : Datatype, varName : String, 
                        params : Array<TailCallSelfParam>) {
        super(sourceRef, datatype, varName);
        mParams = params;
    }

    public override function toSrc(target : LanguageTarget, ctx : SourceCreationContext) {
        return target.makeTailCallSelf(ctx, this);
    }
    public function getParams() {
        return mParams;
    }
}