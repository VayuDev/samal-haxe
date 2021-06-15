package samal;

import haxe.macro.Expr;
import haxe.Int32;
import samal.Tokenizer.SourceCodeRef;
import samal.AST;
import samal.Util;

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
}

class SamalDeclarationNode extends SamalASTNode {

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
        return super.dumpSelf() + " " + mName.dump() + " " + getDatatype();
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
    public function getStatements() {
        return mStatements;
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