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
    var mBaseFileName : String;

    public function new(baseFileName : String, code : String) {
        mTokenizer = new Tokenizer(code);
        mBaseFileName = baseFileName;
    }
    public function parse() : SamalModuleNode {
        startNode();
        var moduleName = mBaseFileName;
        skipNewlines();
        if(current().getType() == TokenType.Module) {
            eat(TokenType.Module);
            moduleName = current().getSubstr();
            eat(TokenType.Identifier);
            eat(TokenType.NewLine);
        }
        var decls : Array<SamalDeclarationNode> = [];
        while(current().getType() != TokenType.Invalid) {
            skipNewlines();
            var decl = parseDeclaration();
            if(decl != null) {
                decls.push(decl);
            }
            skipNewlines();
        }
        return new SamalModuleNode(makeSourceRef(), moduleName, decls);
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
                startNode();
                var body = parseScope();
                return new SamalFunctionDeclarationNode(makeSourceRef(), identifier, params, returnType, body);
            case _:
                throw new Exception(current().info() + ": Expected declaration");
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
                throw new Exception(current().info() + ": Expected datatype");
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

    function parseTemplateParams() : Array<Datatype> {
        return [];
    }

    function parseIdentifierWithTemplate() : IdentifierWithTemplate {
        var str = current().getSubstr();
        eat(TokenType.Identifier);
        return new IdentifierWithTemplate(str, parseTemplateParams());
    }

    function parseScope() : SamalScope {
        startNode();
        eat(TokenType.LCurly);
        var statements = [];
        while(current().getType() != TokenType.RCurly) {
            skipNewlines();
            statements.push(parseExpression());
            eat(TokenType.NewLine);
            skipNewlines();
        }
        eat(TokenType.RCurly);
        return new SamalScope(makeSourceRef(), statements);
    }

    function parseExpression() : SamalExpression {
        return parseBinaryExpression([[
            TokenType.FunctionChain => SamalBinaryExpressionOp.FunctionChain
        ], [
            TokenType.Less => SamalBinaryExpressionOp.Less,
            TokenType.More => SamalBinaryExpressionOp.More,
            TokenType.LessEqual => SamalBinaryExpressionOp.LessEqual,
            TokenType.MoreEqual => SamalBinaryExpressionOp.MoreEqual
        ], [
            TokenType.Plus => SamalBinaryExpressionOp.Add,
            TokenType.Minus => SamalBinaryExpressionOp.Sub
        ]]);
    }

    function parseBinaryExpression(binaryExprInfo : Array<Map<TokenType, SamalBinaryExpressionOp>>) : SamalExpression {
        if(binaryExprInfo.length == 0) {
            return parsePostfixExpression();
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

    function parseExpressionList() : Array<SamalExpression> {
        eat(LParen);
        var ret = [];
        while(current().getType() != RParen) {
            ret.push(parseExpression());
            if(current().getType() == Comma) {
                eat(Comma);
            } else {
                break;
            }
        }
        eat(RParen);
        return ret;
    }

    function parsePostfixExpression() : SamalExpression {
        startNode();
        var lhs = parseLiteralExpression();
        while(current().getType() == TokenType.LParen) {
            var params = parseExpressionList();
            lhs = new SamalFunctionCallExpression(makeSourceRef(), lhs, params);
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
            case TokenType.LCurly:
                startNode();
                return new SamalScopeExpression(makeSourceRef(), parseScope());
            case TokenType.Identifier:
                startNode();
                if (peek().getType() == TokenType.Equals) {
                    var identifierName = current().getSubstr();
                    eat(TokenType.Identifier);
                    eat(TokenType.Equals);
                    var rhs = parseExpression();
                    return new SamalAssignmentExpression(makeSourceRef(), identifierName, rhs);
                }
                return new SamalLoadIdentifierExpression(makeSourceRef(), parseIdentifierWithTemplate());
            case TokenType.If:
                startNode();
                eat(If);
                var mainCondition = parseExpression();
                var mainBody = parseScope();
                var elseIfs = [];
                while(current().getType() == Else && peek().getType() == If) {
                    eat(Else);
                    eat(If);
                    var branchCondition = parseExpression();
                    var branchBody = parseScope();
                    elseIfs.push(new SamalElseIfBranch(branchCondition, branchBody));
                }
                var elseScope;
                if(current().getType() == Else) {
                    eat(Else);
                    elseScope = parseScope();
                } else {
                    throw new Exception("TODO");
                    //elseScope = new SamalScope(makeSourceRefNonDestructive(), )
                }
                return new SamalIfExpression(makeSourceRef(), mainCondition, mainBody, elseIfs, elseScope);
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
    function peek(n : Int = 1) {
        return mTokenizer.peek(n);
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
        var ref = makeSourceRefNonDestructive();
        mSourceRefs.pop();
        return ref;
    }

    function makeSourceRefNonDestructive() : SourceCodeRef {

        var base = mSourceRefs.first();
        if(base == null) {
            throw new Exception("Unexpected mSourceRefs is empty");
        }
        return SourceCodeRef.merge(base, mTokenizer.current().getSourceRef(), mTokenizer.getOriginalString());
    }
}