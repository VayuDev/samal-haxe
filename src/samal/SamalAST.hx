package samal;

import samal.Datatype.StringToDatatypeMapper;
import cloner.Cloner;
import haxe.macro.Expr;
import haxe.Int32;
import samal.Tokenizer.SourceCodeRef;
import samal.AST;
import samal.Util;
using samal.Util.NullTools;
using samal.Datatype.DatatypeHelpers;

class SamalASTNode extends ASTNode {
    public function new(sourceRef : SourceCodeRef) {
        super(sourceRef);
    }
}

class SamalModuleNode extends SamalASTNode {
    var mDeclarations : Array<SamalDeclarationNode>;
    var mModuleName : String;
    public function new(sourceRef : SourceCodeRef, moduleName : String, declarations : Array<SamalDeclarationNode>) {
        super(sourceRef);
        mDeclarations = declarations;
        mModuleName = moduleName;
    }
    public override function replaceChildren(preorder : (ASTNode) -> ASTNode, postorder : (ASTNode) -> ASTNode) {
        mDeclarations = Util.replaceNodes(mDeclarations, preorder, postorder);
    }
    public function getDeclarations() {
        return mDeclarations;
    }
    public function getModuleName() {
        return mModuleName;
    }
    public function setDeclarations(decls : Array<SamalDeclarationNode>) {
        mDeclarations = decls;
    }
}

abstract class SamalDeclarationNode extends SamalASTNode {
    abstract public function getName() : String;
    abstract public function getTemplateParams() : Array<Datatype>;
    abstract public function cloneWithTemplateParams(typeMap : StringToDatatypeMapper, templateParams : Array<Datatype>, cloner : Cloner) : SamalDeclarationNode;
    abstract public function completeWithUserTypeMap(mapper : StringToDatatypeMapper) : Void;
}

class SamalFunctionDeclarationNode extends SamalDeclarationNode {
    var mName : IdentifierWithTemplate;
    var mParams : Array<NamedAndTypedParameter>;
    var mReturnType : Datatype;
    var mBody : SamalScope;
    public function new(sourceRef : SourceCodeRef, name : IdentifierWithTemplate, params : Array<NamedAndTypedParameter>, returnType : Datatype, body : SamalScope) {
        super(sourceRef);
        this.mName = name;
        this.mParams = params;
        this.mReturnType = returnType;
        this.mBody = body;
    }
    public override function replaceChildren(preorder : (ASTNode) -> ASTNode, postorder : (ASTNode) -> ASTNode) {
        mBody = cast(mBody.replace(preorder, postorder), SamalScope);
    }
    public override function dumpSelf() : String {
        return "\n" + super.dumpSelf() + " " + mName.dump() + " " + getDatatype();
    }
    public function completeWithUserTypeMap(mapper : StringToDatatypeMapper) {
        mReturnType = mReturnType.complete(mapper);
        mParams = mParams.map(function(p) {
            return new NamedAndTypedParameter(p.getName(), p.getDatatype().complete(mapper));
        });
    }
    public function getDatatype() : Datatype {
        return Datatype.Function(mReturnType, mParams.map(function(p) {return p.getDatatype();}));
    }
    public function getBody() {
        return mBody;
    }
    public function getIdentifier() {
        return mName;
    }
    public function getParams() {
        return mParams;
    }
    public function setIdentifier(identifier) {
        mName = identifier;
    }
    public function getName() : String {
        return mName.getName();
    }
    public function getTemplateParams() : Array<Datatype> {
        return mName.getTemplateParams();
    }
    public function cloneWithTemplateParams(mapper : StringToDatatypeMapper, templateParams : Array<Datatype>, cloner : Cloner) : SamalFunctionDeclarationNode {
        final params = mParams.map(function(p) {
            return new NamedAndTypedParameter(p.getName(), p.getDatatype().complete(mapper));
        });
        final body = cloner.clone(mBody);
        final returnType = cloner.clone(mReturnType);
        return new SamalFunctionDeclarationNode(getSourceRef(), new IdentifierWithTemplate(getName(), templateParams), params, returnType.complete(mapper), body);
    }
}

abstract class SamalDatatypeDeclaration extends SamalDeclarationNode {
    abstract public function getDatatype() : Datatype;
}

class SamalStructDeclaration extends SamalDatatypeDeclaration {    
    var mName : IdentifierWithTemplate;
    var mFields : Array<StructField>;
    public function new(sourceRef : SourceCodeRef, name : IdentifierWithTemplate, fields : Array<StructField>) {
        super(sourceRef);
        mName = name;
        mFields = fields;
    }
    public override function dumpSelf() : String {
        return "\n" + super.dumpSelf() + " " + getDatatype();
    }
    public function getDatatype() : Datatype {
        return Datatype.Struct(mName.getName(), mName.getTemplateParams());
    }
    public function getIdentifier() {
        return mName;
    }
    public function getFields() {
        return mFields;
    }
    public function setIdentifier(identifier) {
        mName = identifier;
    }
    public function getName() : String {
        return mName.getName();
    }
    public function getTemplateParams() : Array<Datatype> {
        return mName.getTemplateParams();
    }
    public function cloneWithTemplateParams(mapper : StringToDatatypeMapper, templateParams : Array<Datatype>, cloner : Cloner) : SamalStructDeclaration {
        final fields = mFields.map(function(p) {
            return new StructField(p.getName(), p.getDatatype().complete(mapper));
        });
        return new SamalStructDeclaration(getSourceRef(), new IdentifierWithTemplate(getName(), templateParams), fields);
    }
    public function completeWithUserTypeMap(mapper : StringToDatatypeMapper) : Void {
        mFields = mFields.map(function(p) {
            return new StructField(p.getName(), p.getDatatype().complete(mapper));
        });
    }
}

class SamalExpression extends SamalASTNode {
    var mDatatype : Null<Datatype>;

    public override function dumpSelf() : String {
        if(getDatatype() == null) {
            return super.dumpSelf() + " ()";
        } else {
            return super.dumpSelf() + " (" + NullTools.sure(getDatatype()) + ")";
        }
    }

    public function setDatatype(datatype : Datatype) {
        mDatatype = datatype;
    }

    public function getDatatype() : Null<Datatype> {
        return mDatatype;
    }
}

enum SamalBinaryExpressionOp {
    Add;
    Sub;
    FunctionChain;
    Less;
    More;
    LessEqual;
    MoreEqual;
}

class SamalBinaryExpression extends SamalExpression {
    var mLhs : SamalExpression;
    var mOp : SamalBinaryExpressionOp;
    var mRhs : SamalExpression;
    public function new(sourceRef : SourceCodeRef, lhs : SamalExpression, op : SamalBinaryExpressionOp, rhs : SamalExpression) {
        super(sourceRef);
        mLhs = lhs;
        mOp = op;
        mRhs = rhs;
    }
    public function getLhs() {
        return mLhs;
    }
    public function getRhs() {
        return mRhs;
    }
    public function getOperator() {
        return mOp;
    }
    public override function replaceChildren(preorder : (ASTNode) -> ASTNode, postorder : (ASTNode) -> ASTNode) {
        mLhs = cast(mLhs.replace(preorder, postorder), SamalExpression);
        mRhs = cast(mRhs.replace(preorder, postorder), SamalExpression);
    }
    public override function dumpSelf() : String {
        return super.dumpSelf() + ": " + mOp;
    }
}

enum SamalUnaryExpressionOp {
    Not;
}

class SamalUnaryExpression extends SamalExpression {
    var mExpr : SamalExpression;
    var mOp : SamalUnaryExpressionOp;
    public function new(sourceRef : SourceCodeRef, op : SamalUnaryExpressionOp, expr : SamalExpression) {
        super(sourceRef);
        mExpr = expr;
        mOp = op;
    }
    public override function replaceChildren(preorder : (ASTNode) -> ASTNode, postorder : (ASTNode) -> ASTNode) {
        mExpr = cast(mExpr.replace(preorder, postorder), SamalExpression);
    }
    public function getExpression() {
        return mExpr;
    }
    public function getOperator() {
        return mOp;
    }
}

class SamalLiteralIntExpression extends SamalExpression {
    var mVal : Int32;
    public function new(sourceRef : SourceCodeRef, val : Int32) {
        super(sourceRef);
        mVal = val;
        mDatatype = Datatype.Int;
    }
    public override function dumpSelf() : String {
        return super.dumpSelf() + ": " + mVal;
    }
    public function getValue() {
        return mVal;
    }
}

class SamalScope extends SamalASTNode {
    var mStatements : Array<SamalExpression>;
    var mDatatype : Null<Datatype>;
    public function new(sourceRef : SourceCodeRef, statements : Array<SamalExpression>) {
        super(sourceRef);
        mStatements = statements;
    }
    public override function replaceChildren(preorder : (ASTNode) -> ASTNode, postorder : (ASTNode) -> ASTNode) {
        mStatements = Util.replaceNodes(mStatements, preorder, postorder);
    }
    public function getStatements() : Array<SamalExpression> {
        return mStatements;
    }
    public function addStatement(stmt : SamalExpression) {
        mStatements.push(stmt);
    }
    public function setDatatype(type : Datatype) {
        mDatatype = type;
    }

    public function getDatatype() {
        return mDatatype;
    }
    public override function dumpSelf() : String {
        if(mDatatype == null) {
            return super.dumpSelf() + " ()";
        } else {
            return super.dumpSelf() + " (" + NullTools.sure(mDatatype) + ")";
        }
    }
}

class SamalScopeExpression extends SamalExpression {
    var mScope : SamalScope;
    public function new(sourceRef : SourceCodeRef, scope : SamalScope) {
        super(sourceRef);
        mScope = scope;
    }
    public override function replaceChildren(preorder : (ASTNode) -> ASTNode, postorder : (ASTNode) -> ASTNode) {
        mScope = cast(mScope.replace(preorder, postorder), SamalScope);
    }
    public function getScope() : SamalScope {
        return mScope;
    }
    public override function getDatatype() {
        return mScope.getDatatype();
    }
    public override function setDatatype(datatype : Datatype) {
        mDatatype = datatype;
        mScope.setDatatype(datatype);
    }
}

class SamalAssignmentExpression extends SamalExpression {
    var mIdentifier : String;
    var mRhs : SamalExpression;
    public function new(sourceRef : SourceCodeRef, identifier : String, rhs : SamalExpression) {
        super(sourceRef);
        mIdentifier = identifier;
        mRhs = rhs;
    }
    public override function replaceChildren(preorder : (ASTNode) -> ASTNode, postorder : (ASTNode) -> ASTNode) {
        mRhs = cast(mRhs.replace(preorder, postorder), SamalExpression);
    }
    public function getRhs() {
        return mRhs;
    }
    public function getIdentifier() {
        return mIdentifier;
    }
    public override function dumpSelf() : String {
        return super.dumpSelf() + ' Assigning to "${mIdentifier}"';
    }
    public function setIdentifier(ident : String) {
        mIdentifier = ident;
    }
}

class SamalLoadIdentifierExpression extends SamalExpression {
    var mIdentifier : IdentifierWithTemplate;
    public function new(sourceRef : SourceCodeRef, identifier : IdentifierWithTemplate) {
        super(sourceRef);
        mIdentifier = identifier;
    }
    public function getIdentifier() {
        return mIdentifier;
    }
    public override function dumpSelf() : String {
        return super.dumpSelf() + ' Loading from "${mIdentifier.dump()}"';
    }
    public function setIdentifier(identifier : IdentifierWithTemplate) {
        mIdentifier = identifier;
    }
}

class SamalFunctionCallExpression extends SamalExpression {
    var mFunction : SamalExpression;
    var mParams : Array<SamalExpression>;
    public function new(sourceRef : SourceCodeRef, func : SamalExpression, params : Array<SamalExpression>) {
        super(sourceRef);
        mFunction = func;
        mParams = params;
    }
    
    public override function replaceChildren(preorder : (ASTNode) -> ASTNode, postorder : (ASTNode) -> ASTNode) {
        mFunction = cast(mFunction.replace(preorder, postorder), SamalExpression);
        mParams = Util.replaceNodes(mParams, preorder, postorder);
    }

    public function getFunction() {
        return mFunction;
    }

    public function getParams() {
        return mParams;
    }
}

class SamalElseIfBranch {
    var mCondition : SamalExpression;
    var mBody : SamalScope;
    public function new(condition : SamalExpression, body : SamalScope) {
        mCondition = condition;
        mBody = body;
    }
    public function getCondition() {
        return mCondition;
    }
    public function getBody() {
        return mBody;
    }
}

class SamalIfExpression extends SamalExpression {
    var mCondition : SamalExpression;
    var mMainBody : SamalScope;
    var mElseIfs : Array<SamalElseIfBranch>;
    var mElse : SamalScope;
    public function new(sourceRef : SourceCodeRef, condition : SamalExpression, mainBody : SamalScope, elseIfs : Array<SamalElseIfBranch>, elseBody : SamalScope) {
        super(sourceRef);
        mCondition = condition;
        mMainBody = mainBody;
        mElseIfs = elseIfs;
        mElse = elseBody;
    }
    public function getMainCondition() {
        return mCondition;
    }
    public function getMainBody() {
        return mMainBody;
    }
    public function getElseIfs() {
        return mElseIfs;
    }
    public function getElse() {
        return mElse;
    }
    public function getAllBranches() : Array<SamalElseIfBranch> {
        return [new SamalElseIfBranch(mCondition, mMainBody)].concat(mElseIfs);
    }
    
    public override function replaceChildren(preorder : (ASTNode) -> ASTNode, postorder : (ASTNode) -> ASTNode) {
        mCondition = cast(mCondition.replace(preorder, postorder), SamalExpression);
        mMainBody = cast(mMainBody.replace(preorder, postorder), SamalScope);
        for(elsif in mElseIfs) {
            elsif = new SamalElseIfBranch(
                cast(elsif.getCondition().replace(preorder, postorder), SamalExpression),
                cast(elsif.getBody().replace(preorder, postorder), SamalScope)
            );
        }
        mElse = cast(mElse.replace(preorder, postorder), SamalScope);
    }
}

class SamalSimpleIfExpression extends SamalExpression {
    var mCondition : SamalExpression;
    var mMainBody : SamalScope;
    var mElseBody : SamalScope;
    public function new(sourceRef : SourceCodeRef, condition : SamalExpression, mainBody : SamalScope, elseBody : SamalScope) {
        super(sourceRef);
        mCondition = condition;
        mMainBody = mainBody;
        mElseBody = elseBody;
    }
    public function getMainCondition() {
        return mCondition;
    }
    public function getMainBody() {
        return mMainBody;
    }
    public function getElseBody() {
        return mElseBody;
    }
    
    public override function replaceChildren(preorder : (ASTNode) -> ASTNode, postorder : (ASTNode) -> ASTNode) {
        mCondition = cast(mCondition.replace(preorder, postorder), SamalExpression);
        mMainBody = cast(mMainBody.replace(preorder, postorder), SamalScope);
        mElseBody = cast(mElseBody.replace(preorder, postorder), SamalScope);
    }
}

class SamalCreateStructExpression extends SamalExpression {
    final mStructName : IdentifierWithTemplate;
    var mParams : Array<NamedAndValuedParameter>;
    public function new(sourceRef : SourceCodeRef, structName : IdentifierWithTemplate, params : Array<NamedAndValuedParameter>) {
        super(sourceRef);
        mStructName = structName;
        mParams = params;
        mDatatype = Datatype.Usertype(mStructName.getName(), mStructName.getTemplateParams());
    }
    
    public override function replaceChildren(preorder : (ASTNode) -> ASTNode, postorder : (ASTNode) -> ASTNode) {
        mParams = mParams.map(function(p) {
            return new NamedAndValuedParameter(p.getName(), cast(p.getValue().replace(preorder, postorder), SamalExpression));
        });
    }
    public function getParams() {
        return mParams;
    }
}

class SamalCreateListExpression extends SamalExpression {
    var mChildren : Array<SamalExpression>;
    public function new(sourceRef : SourceCodeRef, baseType : Null<Datatype>, children : Array<SamalExpression>) {
        super(sourceRef);
        if(baseType != null) {
            mDatatype = Datatype.List(baseType.sure());
        }
        mChildren = children;
    }
    public function getChildren() {
        return mChildren;
    }
    
    public override function replaceChildren(preorder : (ASTNode) -> ASTNode, postorder : (ASTNode) -> ASTNode) {
        mChildren = Util.replaceNodes(mChildren, preorder, postorder);
    }
}

class SamalSimpleCreateEmptyList extends SamalExpression {
    public function new(sourceRef : SourceCodeRef, listType : Datatype) {
        super(sourceRef);
        mDatatype = listType;
    }
}

class SamalSimpleListPrepend extends SamalExpression {
    var mValue : SamalExpression;
    var mList : SamalExpression;
    public function new(sourceRef : SourceCodeRef, listType : Datatype, value : SamalExpression, list : SamalExpression) {
        super(sourceRef);
        mDatatype = listType;
        mValue = value;
        mList = list;
    }
    public function getValue() {
        return mValue;
    }
    public function getList() {
        return mList;
    }
    
    public override function replaceChildren(preorder : (ASTNode) -> ASTNode, postorder : (ASTNode) -> ASTNode) {
        mValue = cast(mValue.replace(preorder, postorder), SamalExpression);
        mList = cast(mList.replace(preorder, postorder), SamalExpression);
    }
}

class SamalShape extends ASTNode {
    
}

class SamalShapeEmptyList extends SamalShape {
    public function new(sourceRef : SourceCodeRef) {
        super(sourceRef);
    }
}
class SamalShapeSplitList extends SamalShape {
    var mHead : SamalShape;
    var mTail : SamalShape;
    public function new(sourceRef : SourceCodeRef, head : SamalShape, tail : SamalShape) {
        super(sourceRef);
        mHead = head;
        mTail = tail;
    }
    public function getHead() {
        return mHead;
    }
    public function getTail() {
        return mTail;
    }
    
    public override function replaceChildren(preorder : (ASTNode) -> ASTNode, postorder : (ASTNode) -> ASTNode) {
        mHead = cast(mHead.replace(preorder, postorder), SamalShape);
        mTail = cast(mTail.replace(preorder, postorder), SamalShape);
    }
}
class SamalShapeVariable extends SamalShape {
    var mVariableName : String;
    public function new(sourceRef : SourceCodeRef, variableName : String) {
        super(sourceRef);
        mVariableName = variableName;
    }

    public function getVariableName() {
        return mVariableName;
    }
}

class SamalMatchRow extends SamalASTNode {
    var mShape : SamalShape;
    var mBody : SamalExpression;
    public function new(sourceRef : SourceCodeRef, shape : SamalShape, body : SamalExpression) {
        super(sourceRef);
        mShape = shape;
        mBody = body;
    }
    public function getShape() {
        return mShape;
    }
    public function getBody() {
        return mBody;
    }
    
    public override function replaceChildren(preorder : (ASTNode) -> ASTNode, postorder : (ASTNode) -> ASTNode) {
        mShape = cast(mShape.replace(preorder, postorder), SamalShape);
        mBody = cast(mBody.replace(preorder, postorder), SamalExpression);
    }
}

class SamalMatchExpression extends SamalExpression {
    var mToMatch : SamalExpression;
    var mRows : Array<SamalMatchRow>;
    public function new(sourceRef : SourceCodeRef, toMatch : SamalExpression, rows : Array<SamalMatchRow>) {
        super(sourceRef);
        mToMatch = toMatch;
        mRows = rows;
    }
    public function getToMatch() {
        return mToMatch;
    }
    public function getRows() {
        return mRows;
    }
    
    public override function replaceChildren(preorder : (ASTNode) -> ASTNode, postorder : (ASTNode) -> ASTNode) {
        mToMatch = cast(mToMatch.replace(preorder, postorder), SamalExpression);
        mRows = Util.replaceNodes(mRows, preorder, postorder);
    }
}


class SamalSimpleListGetHead extends SamalExpression {
    var mList : SamalExpression;
    public function new(sourceRef : SourceCodeRef, listType : Datatype, list : SamalExpression) {
        super(sourceRef);
        mDatatype = listType.getBaseType();
        mList = list;
    }
    public function getList() {
        return mList;
    }
}
class SamalSimpleListGetTail extends SamalExpression {
    var mList : SamalExpression;
    public function new(sourceRef : SourceCodeRef, listType : Datatype, list : SamalExpression) {
        super(sourceRef);
        mDatatype = listType;
        mList = list;
    }
    public function getList() {
        return mList;
    }
}
class SamalSimpleListIsEmpty extends SamalExpression {
    var mList : SamalExpression;
    public function new(sourceRef : SourceCodeRef, list : SamalExpression) {
        super(sourceRef);
        mDatatype = Bool;
        mList = list;
    }
    public function getList() {
        return mList;
    }
}

class SamalSimpleUnreachable extends SamalExpression {
    public function new(sourceRef : SourceCodeRef) {
        super(sourceRef);
    }
}


class SamalCreateLambdaExpression extends SamalExpression {
    final mParameters : Array<NamedAndTypedParameter>;
    final mReturnType : Datatype;
    var mBody : SamalScope;
    final mCapturedVariables : Array<NamedAndTypedParameter> = [];
    public function new(sourceRef : SourceCodeRef, parameters: Array<NamedAndTypedParameter>, returnType : Datatype, body : SamalScope) {
        super(sourceRef);    
        mParameters = parameters;
        mReturnType = returnType;
        mBody = body;
        mDatatype = Datatype.Function(returnType, parameters.map(function(p) return p.getDatatype()));
    }
    public function getParams() {
        return mParameters;
    }
    public function getReturnType() {
        return mReturnType;
    }
    public function getBody() {
        return mBody;
    }
    public override function replaceChildren(preorder : (ASTNode) -> ASTNode, postorder : (ASTNode) -> ASTNode) {
        mBody = cast(mBody.replace(preorder, postorder), SamalScope);
    }
    public function addCapturedVariable(name : NamedAndTypedParameter) {
        mCapturedVariables.push(name);
    }
    public function getCapturedVariables() {
        return mCapturedVariables;
    }
    public override function dumpSelf() : String {
        return super.dumpSelf() + " Captured: <" + mCapturedVariables.join(", ") + ">";
    }
}

class SamalLineExpression extends SamalExpression {

}

class SamalTailCallSelf extends SamalLineExpression {
    final mParameters : Array<SamalExpression>;
    public function new(sourceRef : SourceCodeRef, params : Array<SamalExpression>) {
        super(sourceRef);
        mParameters = params;
    }
    public function getParams() {
        return mParameters;
    }
}

class SamalSimpleTailCallSelf extends SamalLineExpression {
    final mParameters : Array<NamedAndValuedParameter>;
    public function new(sourceRef : SourceCodeRef, datatype : Datatype, params : Array<NamedAndValuedParameter>) {
        super(sourceRef);
        mParameters = params;
        mDatatype = datatype;
    }
    public function getParams() {
        return mParameters;
    }
}