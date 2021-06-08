package samal;
import haxe.Int32;
import samal.SamalAST;
import haxe.Exception;
import samal.Tokenizer;
import haxe.macro.Expr;

import samal.AST;
import haxe.ds.GenericStack;
import samal.Util;

using samal.Util.NullTools;

class Parser {
    var mTokenizer : Tokenizer;
    var mInError = false;
    var mSourceRefs = new GenericStack<SourceCodeRef>();

    public function new(code : String) {
        mTokenizer = new Tokenizer(code);
    }
    public function parse() : SamalModuleNode {
        startNode();
        var decls : Array<SamalDeclarationNode> = [];
        while(current().getType() != TokenType.Invalid) {
            skipNewlines();
            var decl = parseDeclaration();
            if(decl != null) {
                decls.push(decl);
            }
            skipNewlines();
        }
        return new SamalModuleNode(makeSourceRef(), decls);
    }

    function parseDeclaration() : Null<SamalDeclarationNode> {
        startNode();
        switch (current().getType()) {
            case TokenType.Fn:
                eat(TokenType.Fn);
                var identifier = parseIdentifierWithTemplate();
                var params = parseFunctionParameterList();
                eat(TokenType.RightArrow);
                var returnType = parseDatatype();
                var body = parseScope();
                return new SamalFunctionDeclarationNode(makeSourceRef(), identifier, params, returnType, body);
            case _:
                throw new Exception(current().info() + " Expected declaration");
        }
        return null;
    }

    function parseDatatype() : Datatype {
        switch(current().getType()) {
            case TokenType.Int:
                eat(TokenType.Int);
                return Datatype.Int;
            case TokenType.Bool:
                eat(TokenType.Bool);
                return Datatype.Bool;
            case _:
                throw new Exception(current().info() + " Expected datatype");
        }
    }

    function parseFunctionParameterList() : Array<NamedAndTypedParameter> {
        var ret = [];
        eat(TokenType.LParen);
        while(current().getType() != TokenType.RParen) {
            var name = current().getSubstr();
            eat(TokenType.Identifier);
            eat(TokenType.Colons);
            var type = parseDatatype();
            ret.push(new NamedAndTypedParameter(name, type));
            if(current().getType() == TokenType.Comma) {
                eat(TokenType.Comma);
            } else {
                break;
            }
        }
        eat(TokenType.RParen);
        
        return ret;
    }

    function parseIdentifierWithTemplate() : IdentifierWithTemplate {
        var str = current().getSubstr();
        eat(TokenType.Identifier);
        return new IdentifierWithTemplate(str, []);
    }

    function parseScope() : SamalScope {
        startNode();
        eat(TokenType.LCurly);
        var statements = [];
        while(current().getType() != TokenType.RCurly) {
            skipNewlines();
            statements.push(parseStatement());
            eat(TokenType.NewLine);
            skipNewlines();
        }
        eat(TokenType.RCurly);
        return new SamalScope(makeSourceRef(), statements);
    }

    function parseStatement() : SamalStatement {
        try {
            mTokenizer.push();
            var ret = parseExpression();
            mTokenizer.acceptState();
            return ret;
        } catch(e) {
            mTokenizer.pop();
            throw e;
        }
    }

    function parseExpression() : SamalExpression {
        return parseBinaryExpression([[
            TokenType.FunctionChain => SamalBinaryExpressionOp.FunctionChain
        ], [
            TokenType.Plus => SamalBinaryExpressionOp.Add,
            TokenType.Minus => SamalBinaryExpressionOp.Sub
        ]]);
    }

    function parseBinaryExpression(binaryExprInfo : Array<Map<TokenType, SamalBinaryExpressionOp>>) : SamalExpression {
        if(binaryExprInfo.length == 0) {
            return parseLiteralExpression();
        }
        startNode();
        var nextStepInfo = binaryExprInfo.copy();
        nextStepInfo.shift();
        var lhs = parseBinaryExpression(nextStepInfo);
        while(binaryExprInfo[0].exists(current().getType())) {
            var op = binaryExprInfo[0][current().getType()];
            mTokenizer.next();
            var rhs = parseBinaryExpression(nextStepInfo);
            lhs = new SamalBinaryExpression(makeSourceRef(), lhs, op.sure(), rhs);
            startNode();
        }
        dropNode();
        return lhs;
    }

    function parseLiteralExpression() : SamalExpression {
        startNode();
        switch(current().getType()) {
            case TokenType.Integer:
                var val = current().getSubstr();
                eat(TokenType.Integer);
                var valAsInt = Std.parseInt(val);
                if(valAsInt == null) {
                    throw new Exception(current().info() + " Couldn't convert " + val + " to int");
                }
                return new SamalLiteralIntExpression(makeSourceRef(), valAsInt);
            case _:
                throw new Exception(current().info() + " Expected expression");
        }
    }


    function eat(type : TokenType) {
        mTokenizer.eat(type);
    }

    function current() {
        return mTokenizer.current();
    }

    function skipNewlines() {
        while(mTokenizer.current().getType() == TokenType.NewLine) {
            mTokenizer.next();
        }
    }
    
    function startNode() {
        mSourceRefs.add(mTokenizer.current().getSourceRef());
    }
    function dropNode() {
        mSourceRefs.pop();
    }

    function makeSourceRef() : SourceCodeRef {
        var base = mSourceRefs.first();
        if(base == null) {
            throw new Exception("Unexpected mSourceRefs is empty");
        }
        mSourceRefs.pop();
        return SourceCodeRef.merge(base, mTokenizer.current().getSourceRef(), mTokenizer.getOriginalString());
    }
}