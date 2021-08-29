package samal.lang;
import haxe.Int32;
import samal.lang.generated.SamalAST;
import haxe.Exception;
import samal.bootstrap.Tokenizer;
import haxe.macro.Expr;

import samal.lang.AST;
import haxe.ds.GenericStack;
import samal.lang.Util;

using samal.lang.Util.NullTools;

class Parser {
    var mTokenizer : Tokenizer;
    var mInError = false;
    var mSourceRefs = new GenericStack<SourceCodeRef>();
    var mBaseFileName : String;

    public function new(baseFileName : String, code : String) {
        mTokenizer = new Tokenizer(code, TokenizerMode.Normal);
        mBaseFileName = baseFileName;
    }
    public function parse() : SamalModule {
        startNode();
        var moduleName = mBaseFileName;
        skipNewlines();
        if(current().getType() == TokenType.Module) {
            eat(TokenType.Module);
            moduleName = current().getSubstr();
            eat(TokenType.Identifier);
            eat(TokenType.NewLine);
        }
        var decls : Array<SamalDeclaration> = [];
        while(current().getType() != TokenType.Invalid) {
            skipNewlines();
            var decl = parseDeclaration();
            if(decl != null) {
                decls.push(decl);
            }
            skipNewlines();
        }
        return SamalModule.create(makeSourceRef(), moduleName, decls);
    }

    function parseDeclaration() : Null<SamalDeclaration> {
        startNode();
        switch (current().getType()) {
            case Fn:
                eat(TokenType.Fn);
                var identifier = parseIdentifierWithTemplate();
                var params = parseFunctionParameterList();
                eat(TokenType.RightArrow);
                var returnType = parseDatatype();
                startNode();
                var body = parseScope();
                return SamalFunctionDeclaration.create(makeSourceRef(), identifier, params, returnType, body);
            
            case Struct:
                eat(Struct);
                final identifier = parseIdentifierWithTemplate();
                final fields = parseUsertypeDeclFieldList(NewLine);
                return SamalStructDeclaration.create(makeSourceRef(), identifier, fields);

            case Enum:
                eat(Enum);
                final identifier = parseIdentifierWithTemplate();
                final variants = parseEnumVariantList();
                return SamalEnumDeclaration.create(makeSourceRef(), identifier, variants);

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
                return Datatype.Unknown(ident.getName(), ident.getTemplateParams());
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

    function parseFunctionParameterList() : Array<NameAndTypeParam> {
        var ret = [];
        eat(TokenType.LParen);
        while(current().getType() != TokenType.RParen) {
            var name = current().getSubstr();
            eat(TokenType.Identifier);
            eat(TokenType.Colons);
            var type = parseDatatype();
            ret.push(NameAndTypeParam.create(name, type));
            if(current().getType() == TokenType.Comma) {
                eat(TokenType.Comma);
            } else {
                break;
            }
        }
        eat(TokenType.RParen);
        
        return ret;
    }

    function parseEnumVariantList() : Array<EnumDeclVariant> {
        var ret = [];
        eat(TokenType.LCurly);
        while(current().getType() != TokenType.RCurly) {
            skipNewlines();
            final variantName = eat(Identifier).getSubstr();
            final fields = parseUsertypeDeclFieldList(Comma);
            ret.push(EnumDeclVariant.create(variantName, fields));
            skipNewlines();
        }
        eat(TokenType.RCurly);
        return ret;
    }

    function parseUsertypeField() : UsertypeField {
        final name = current().getSubstr();
        eat(TokenType.Identifier);
        eat(TokenType.Colons);
        final type = parseDatatype();
        return UsertypeField.create(name, type);
    }

    function parseUsertypeDeclFieldList(delimiter : TokenType) : Array<UsertypeField> {
        var ret = [];
        eat(TokenType.LCurly);
        skipNewlines();
        while(current().getType() != TokenType.RCurly) {
            ret.push(parseUsertypeField());
            if(current().getType() == delimiter)
                eat(delimiter);
            else
                break;
        }
        eat(TokenType.RCurly);
        return ret;
    }

    function parseCreateUsertypeParamList() : Array<SamalCreateUsertypeParam> {
        var ret = [];
        eat(TokenType.LCurly);
        while(current().getType() != TokenType.RCurly) {
            var name = current().getSubstr();
            eat(TokenType.Identifier);
            eat(TokenType.Colons);
            var value = parseExpression();
            ret.push(SamalCreateUsertypeParam.create(name, value));
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
        return SamalScope.create(makeSourceRef(), statements);
    }

    function parseExpressionOrLineExpression() : SamalExpression {
        if(current().getType() == At) {
            startNode();
            eat(At);
            final type = current().getSubstr();
            eat(Identifier);
            switch(type) {
                case "tail_call_self":
                    return SamalTailCallSelf.create(makeSourceRef(), parseExpressionList(LParen, RParen));
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
            lhs = SamalBinaryExpression.create(makeSourceRef(), lhs, op.sure(), rhs);
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
            lhs = SamalFunctionCallExpression.create(makeSourceRef(), lhs, params);
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
                return SamalShapeVariable.create(makeSourceRef(), varName);
            case LSquare:
                eat(LSquare);
                if (current().getType() == RSquare) {
                    eat(RSquare);
                    return SamalShapeEmptyList.create(makeSourceRef());
                }
                var head = parseMatchShape();
                eat(Plus);
                var tail = parseMatchShape();
                eat(RSquare);
                return SamalShapeSplitList.create(makeSourceRef(), head, tail);
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
                return SamalLiteralIntExpression.create(makeSourceRef(), valAsInt);
            case TokenType.LCurly:
                startNode();
                return SamalScopeExpression.create(makeSourceRef(), parseScope());
            case TokenType.Identifier:
                startNode();
                if (peek().getType() == TokenType.Equals) {
                    final identifierName = current().getSubstr();
                    eat(TokenType.Identifier);
                    eat(TokenType.Equals);
                    var rhs = parseExpression();
                    return SamalAssignmentExpression.create(makeSourceRef(), identifierName, rhs);
                } else if((peek().getType() == LCurly || peek().getType() == Less) && peek().getSkippedWhitespaces() == 0) {
                    // struct or enum creation or a function call
                    final identifier = parseIdentifierWithTemplate();
                    if(current().getType() == LCurly) {
                        // struct creation
                        final params = parseCreateUsertypeParamList();
                        return SamalCreateStructExpression.create(makeSourceRef(), identifier, params);
                    } else if(current().getType() == Colons) {
                        // enum creation
                        eat(Colons);
                        eat(Colons);
                        final variantName = eat(Identifier).getSubstr();
                        final params = parseCreateUsertypeParamList();
                        return SamalCreateEnumExpression.create(makeSourceRef(), identifier, variantName, params);
                    }
                    // probably just a function call like fib<int>(5), not a struct or enum creation Point<int>{...}
                    return SamalLoadIdentifierExpression.create(makeSourceRef(), identifier);
                }
                return SamalLoadIdentifierExpression.create(makeSourceRef(), parseIdentifierWithTemplate());
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
                    elseIfs.push(SamalElseIfBranch.create(branchCondition, branchBody));
                }
                var elseScope;
                if(current().getType() == Else) {
                    eat(Else);
                    elseScope = parseScope();
                } else {
                    elseScope = SamalScope.create(makeSourceRefNonDestructive(), []);
                }
                return SamalIfExpression.create(makeSourceRef(), mainCondition, mainBody, elseIfs, elseScope);

            case LSquare:
                startNode();
                if (peek().getType() == Colons) {
                    eat(LSquare);
                    eat(Colons);
                    var type = parseDatatype();
                    eat(RSquare);
                    return SamalCreateListExpression.create(makeSourceRef(), [], type);
                }
                var expressions = parseExpressionList(LSquare, RSquare);
                return SamalCreateListExpression.create(makeSourceRef(), expressions, null);

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
                    rows.push(SamalMatchRow.create(makeSourceRef(), shape, body));
                    skipNewlines();
                }

                eat(RCurly);
                return SamalMatchExpression.create(makeSourceRef(), toMatch, rows);

            case Fn:
                startNode();
                eat(Fn);
                final params = parseFunctionParameterList();
                eat(RightArrow);
                final returnType = parseDatatype();
                final body = parseScope();
                return SamalCreateLambdaExpression.create(makeSourceRef(), params, returnType, body, []);
            case _:
                throw new Exception(current().info() + " Expected expression");
        }
    }


    function eat(type : TokenType) : Token {
        final c = current();
        mTokenizer.eat(type);
        return c;
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