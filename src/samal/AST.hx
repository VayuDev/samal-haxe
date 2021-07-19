package samal;
import samal.SamalAST.SamalExpression;
import samal.Tokenizer.SourceCodeRef;
import samal.Util.Util;

class ASTNode {
    var mSourceRef : SourceCodeRef;
    function new(sourceRef : SourceCodeRef) {
        this.mSourceRef = sourceRef;
    }


    public function dump() : String {
        var indent = 0;
        var ret = dumpSelf() + "\n";
        replaceChildren(function(node) {
            indent += 1;
            ret += Util.createIndentStr(indent) + node.dumpSelf() + "\n";
            return node;
        },
        function(node : ASTNode) {
            indent -= 1;
            return node;
        });
        return ret;
    }
    public function dumpSelf() {
        return Type.getClassName(Type.getClass(this));
    }
    public function travserePostorder(postorder : (ASTNode) -> Void) {
        traverse(function(childNode) {
        }, function(childNode) {
            postorder(childNode);
        });
    }
    public function traverse(preorder : (ASTNode) -> Void, postorder : (ASTNode) -> Void) {
        replace(function(childNode) {
            preorder(childNode);
            return childNode;
        }, function(childNode) {
            postorder(childNode);
            return childNode;
        });
    }
    public function replace(preorder : (ASTNode) -> ASTNode, postorder : (ASTNode) -> ASTNode) : ASTNode {
        var self = preorder(this);
        self.replaceChildren(preorder, postorder);
        return postorder(self);
    }
    public function replaceChildren(preorder : (ASTNode) -> ASTNode, postorder : (ASTNode) -> ASTNode) {
    }

    public function errorInfo() : String {
        return mSourceRef.errorInfo() + ": ";
    }
    public function getSourceRef() {
        return mSourceRef;
    }
}

class IdentifierWithTemplate {
    var mIdentifierName : String;
    var mTemplateParams : Array<Datatype>;
    public function new(identifierName, templateParams) {
        mIdentifierName = identifierName;
        mTemplateParams = templateParams;
    }
    public function dump() : String {
        if(mTemplateParams.length == 0) {
            return mIdentifierName;
        }
        return mIdentifierName + "<" + mTemplateParams.map(function(type) {return type.getName();}).join(", ") + ">";
    }
    public function getName() {
        return mIdentifierName;
    }
    public function getTemplateParams() {
        return mTemplateParams;
    }
    public function mangled() {
        return Util.mangle(mIdentifierName, mTemplateParams);
    }
}

class NamedAndTypedParameter {
    var mName : String;
    var mDatatype : Datatype;
    public function new(name : String, datatype : Datatype) {
        mName = name;
        mDatatype = datatype;
    }
    public function getDatatype() {
        return mDatatype;
    }
    public function getName() {
        return mName;
    }
}
class NamedAndValuedParameter {
    var mName : String;
    var mValue : SamalExpression;
    public function new(name : String, value : SamalExpression) {
        mName = name;
        mValue = value;
    }
    public function getValue() {
        return mValue;
    }
    public function getName() {
        return mName;
    }
}