package samal;
import haxe.Int32;
import samal.generated.SamalAST;
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
        mTokenizer = new Tokenizer(code, TokenizerMode.Normal);
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
            
            case TokenType.Struct:
                eat(Struct);
                final identifier = parseIdentifierWithTemplate();
                final fields = parseStructFieldList();
                return new SamalStructDeclaration(makeSourceRef(), identifier, fields);
            case _:
                throw new Exception(current().info() + ": Expected declaration");
        }
        return null;
    }

    function parseDatatype() : Datatype {
        switch(current().getType()) {
            case Int:
                eat(TokenType.Int);
                return Datatype.Int;
            case Bool:
                eat(TokenType.Bool);
                return Datatype.Bool;
            case LSquare:
                eat(LSquare);
                var baseType = parseDatatype();
                eat(RSquare);
                return Datatype.List(baseType);
            case Identifier:
                final ident = parseIdentifierWithTemplate();
                return Datatype.Usertype(ident.getName(), ident.getTemplateParams());
            case Fn:
                eat(Fn);
                final params = parseDatatypeList();
                eat(RightArrow);
                final returnType = parseDatatype();
                return Datatype.Function(returnType, params);
            case _:
                throw new Exception(current().info() + ": Expected datatype");
        }
    }

    function parseDatatypeList() : Array<Datatype> {
        var ret = [];
        eat(LParen);
        while(current().getType() != RParen) {
            ret.push(parseDatatype());
            if(current().getType() == Comma) {
                eat(Comma);
            } else {
                break;
            }
        }
        eat(RParen);
        return ret;
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

    function parseStructFieldList() : Array<StructField> {
        var ret = [];
        eat(TokenType.LCurly);
        while(current().getType() != TokenType.RCurly) {
            skipNewlines();
            var name = current().getSubstr();
            eat(TokenType.Identifier);
            eat(TokenType.Colons);
            var type = parseDatatype();
            ret.push(new StructField(name, type));
            skipNewlines();
        }
        eat(TokenType.RCurly);
        return ret;
    }

    function parseNamedExpressionParameterList() : Array<NamedAndValuedParameter> {
        var ret = [];
        eat(TokenType.LCurly);
        while(current().getType() != TokenType.RCurly) {
            var name = current().getSubstr();
            eat(TokenType.Identifier);
            eat(TokenType.Colons);
            var value = parseExpression();
            ret.push(new NamedAndValuedParameter(name, value));
            if(current().getType() == TokenType.Comma) {
                eat(TokenType.Comma);
            } else {
                break;
            }
        }
        eat(TokenType.RCurly);
        return ret;
    }

    function parseTemplateParams() : Array<Datatype> {
        var templateParams = [];
        if(current().getType() == Less && current().getSkippedWhitespaces() == 0) {
            eat(Less);
            while(current().getType() != More) {
                templateParams.push(parseDatatype());
                if(current().getType() == Comma) {
                    eat(Comma);
                } else {
                    break;
                }
            }
            eat(More);
        }
        return templateParams;
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
            statements.push(parseExpressionOrLineExpression());
            eat(TokenType.NewLine);
            skipNewlines();
        }
        eat(TokenType.RCurly);
        return new SamalScope(makeSourceRef(), statements);
    }

    function parseExpressionOrLineExpression() : SamalExpression {
        if(current().getType() == At) {
            startNode();
            eat(At);
            final type = current().getSubstr();
            eat(Identifier);
            switch(type) {
                case "tail_call_self":
                    return new SamalTailCallSelf(makeSourceRef(), parseExpressionList(LParen, RParen));
                default:
                    throw new Exception("Unknown line statement '" + type + "'");
            }
        }
        return parseExpression();
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

    function parseExpressionList(lterm : TokenType, rterm : TokenType) : Array<SamalExpression> {
        eat(lterm);
        var ret = [];
        while(current().getType() != rterm) {
            ret.push(parseExpression());
            if(current().getType() == Comma) {
                eat(Comma);
            } else {
                break;
            }
        }
        eat(rterm);
        return ret;
    }

    function parsePostfixExpression() : SamalExpression {
        startNode();
        var lhs = parseLiteralExpression();
        while(current().getType() == TokenType.LParen) {
            var params = parseExpressionList(LParen, RParen);
            lhs = new SamalFunctionCallExpression(makeSourceRef(), lhs, params);
            startNode();
        }
        dropNode();
        return lhs;
    }

    function parseMatchShape() : SamalShape {
        startNode();
        switch(current().getType()) {
            case Identifier:
                var varName = current().getSubstr();
                eat(Identifier);
                return new SamalShapeVariable(makeSourceRef(), varName);
            case LSquare:
                eat(LSquare);
                if (current().getType() == RSquare) {
                    eat(RSquare);
                    return new SamalShapeEmptyList(makeSourceRef());
                }
                var head = parseMatchShape();
                eat(Plus);
                var tail = parseMatchShape();
                eat(RSquare);
                return new SamalShapeSplitList(makeSourceRef(), head, tail);
            case _:
                throw new Exception(current().info() + " Expected match shape");
        }
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
                    final identifierName = current().getSubstr();
                    eat(TokenType.Identifier);
                    eat(TokenType.Equals);
                    var rhs = parseExpression();
                    return new SamalAssignmentExpression(makeSourceRef(), identifierName, rhs);
                } else if((peek().getType() == LCurly || peek().getType() == Less) && peek().getSkippedWhitespaces() == 0) {
                    final identifier = parseIdentifierWithTemplate();
                    if(current().getType() != LCurly) {
                        // probably just a function call like fib<int>(5), not a struct creation Point<int>{...}
                        return new SamalLoadIdentifierExpression(makeSourceRef(), identifier);
                    }
                    final params = parseNamedExpressionParameterList();
                    return new SamalCreateStructExpression(makeSourceRef(), identifier, params);
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
                    elseScope = new SamalScope(makeSourceRefNonDestructive(), []);
                }
                return new SamalIfExpression(makeSourceRef(), mainCondition, mainBody, elseIfs, elseScope);

            case LSquare:
                startNode();
                if (peek().getType() == Colons) {
                    eat(LSquare);
                    eat(Colons);
                    var type = parseDatatype();
                    eat(RSquare);
                    return new SamalCreateListExpression(makeSourceRef(), type, []);
                }
                var expressions = parseExpressionList(LSquare, RSquare);
                return new SamalCreateListExpression(makeSourceRef(), null, expressions);

            case Match:
                startNode();
                eat(Match);
                var toMatch = parseExpression();
                eat(LCurly);
                var rows = [];
                while(current().getType() != RCurly) {
                    skipNewlines();
                    startNode();
                    var shape = parseMatchShape();
                    eat(RightArrow);
                    var body = parseExpression();
                    rows.push(new SamalMatchRow(makeSourceRef(), shape, body));
                    skipNewlines();
                }

                eat(RCurly);
                return new SamalMatchExpression(makeSourceRef(), toMatch, rows);

            case Fn:
                startNode();
                eat(Fn);
                final params = parseFunctionParameterList();
                eat(RightArrow);
                final returnType = parseDatatype();
                final body = parseScope();
                return new SamalCreateLambdaExpression(makeSourceRef(), params, returnType, body);
            case _:
                throw new Exception(current().info() + " Expected expression");
        }
    }


    function eat(type : TokenType) {
        mTokenizer.eat(type);
    }

    function current() : Token {
        return mTokenizer.current();
    }
    function peek(n : Int = 1) {
        return mTokenizer.peek(n);
    }

    function skipNewlines() {
        mTokenizer.skipNewlines();
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