package samal;
import samal.Tokenizer.SourceCodeRef;

class ASTNode {
    var sourceRef : SourceCodeRef;
    function new(sourceRef : SourceCodeRef) {
        this.sourceRef = sourceRef;
    }

    function createIndentStr(indent : Int) : String {
        var ret = "";
        for(i in 0...indent) {
            ret += " ";
        }
        return ret;
    }

    public function dump() : String {
        var indent = 0;
        var ret = dumpSelf() + "\n";
        replaceChildren(function(node) {
            indent += 1;
            ret += createIndentStr(indent) + node.dumpSelf() + "\n";
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
}

class IdentifierWithTemplate {
    var mIdentifierName : String;
    var mTemplateParams : Array<Datatype>;
    public function new(identifierName, templateParams) {
        mIdentifierName = identifierName;
        mTemplateParams = templateParams;
    }
    public function dump() : String {
        return mIdentifierName + "<" + mTemplateParams.map(function(type) {type.getName();}).join(", ") + ">";
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
}