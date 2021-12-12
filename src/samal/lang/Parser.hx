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
        final ret = SamalModule.create(makeSourceRef(), moduleName, decls);
        if(!mSourceRefs.isEmpty()) {
            for(ref in mSourceRefs) {
                trace(ref.info());
            }
            throw new Exception("Assert: Souce code refs remaining!");
        }
        return ret;
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
            case Byte:
                eat(Byte);
                return Datatype.Byte;
            case Char:
                eat(TokenType.Char);
                return Datatype.Char;
            case LSquare:
                eat(LSquare);
                var baseType = parseDatatype();
                eat(RSquare);
                return Datatype.List(baseType);

            case LParen:
                return Tuple(parseList(LParen, Comma, RParen, function() {
                    return parseDatatype();
                }));

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

    @:generic
    function parseList<T>(start : TokenType, separator : TokenType, end : TokenType, parser : () -> T) : Array<T> {
        final ret = [];
        eat(start);
        skipNewlines();
        while(current().getType() != end) {
            ret.push(parser());
            if(current().getType() == separator) {
                eat(separator);
            } else {
                break;
            }
            skipNewlines();
        }
        skipNewlines();
        eat(end);

        return ret;
    }

    function parseDatatypeList() : Array<Datatype> {
        return parseList(LParen, Comma, RParen, function() {
            return parseDatatype();
        });
    }

    function parseFunctionParameterList() : Array<NameAndTypeParam> {
        return parseList(LParen, Comma, RParen, function() {
            final name = current().getSubstr();
            eat(TokenType.Identifier);
            eat(TokenType.Colons);
            final type = parseDatatype();
            return NameAndTypeParam.create(name, type);
        });
    }

    function parseEnumVariantList() : Array<EnumDeclVariant> {
        return parseList(LCurly, NewLine, RCurly, function() {
            final variantName = eat(Identifier).getSubstr();
            final fields = parseUsertypeDeclFieldList(Comma);
            return EnumDeclVariant.create(variantName, fields);
        });
    }

    function parseUsertypeField() : UsertypeField {
        final name = eat(TokenType.Identifier).getSubstr();
        eat(TokenType.Colons);
        final type = parseDatatype();
        return UsertypeField.create(name, type);
    }

    function parseUsertypeDeclFieldList(delimiter : TokenType) : Array<UsertypeField> {
        return parseList(LCurly, delimiter, RCurly, function() {
            return parseUsertypeField();
        });
    }

    function parseCreateUsertypeParamList() : Array<SamalCreateUsertypeParam> {
        return parseList(LCurly, Comma, RCurly, function() {
            final name = eat(TokenType.Identifier).getSubstr();
            eat(TokenType.Colons);
            final value = parseExpression();
            return SamalCreateUsertypeParam.create(name, value);
        });
    }

    function parseTemplateParams() : Array<Datatype> {
        if(current().getType() != Less || current().getSkippedWhitespaces() != 0) {
            return [];
        }
        return parseList(Less, Comma, More, function() {
            return parseDatatype();
        });
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
        if(current().getType() == At && peek().getType() == At) {
            startNode();
            eat(At);
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
            TokenType.DoubleAnd => SamalBinaryExpressionOp.And,
            TokenType.DoublePipe => SamalBinaryExpressionOp.Or,
        ], [
            TokenType.DoubleEquals => SamalBinaryExpressionOp.Equal,
            TokenType.NotEquals => SamalBinaryExpressionOp.NotEqual,
        ], [
            TokenType.Less => SamalBinaryExpressionOp.Less,
            TokenType.More => SamalBinaryExpressionOp.More,
            TokenType.LessEqual => SamalBinaryExpressionOp.LessEqual,
            TokenType.MoreEqual => SamalBinaryExpressionOp.MoreEqual
        ], [
            TokenType.Plus => SamalBinaryExpressionOp.Add,
            TokenType.Minus => SamalBinaryExpressionOp.Sub
        ], [
            TokenType.Star => SamalBinaryExpressionOp.Mul,
            TokenType.Slash => SamalBinaryExpressionOp.Div
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
        while(binaryExprInfo[0].exists(currentWithoutNewlines().getType())) {
            skipNewlines();
            var op = binaryExprInfo[0][current().getType()].sure();
            mTokenizer.next();
            var rhs = parseBinaryExpression(nextStepInfo);
            lhs = SamalBinaryExpression.create(makeSourceRefNonDestructive(), lhs, op.sure(), rhs);
        }
        dropNode();
        return lhs;
    }

    function parseExpressionList(lterm : TokenType, rterm : TokenType) : Array<SamalExpression> {
        return parseList(lterm, Comma, rterm, function() {
            return parseExpression();
        });
    }

    function parsePostfixExpression() : SamalExpression {
        startNode();
        var lhs = parseLiteralExpression();
        while(current().getType() == TokenType.LParen) {
            var params = parseExpressionList(LParen, RParen);
            lhs = SamalFunctionCallExpression.create(makeSourceRefNonDestructive(), lhs, params);
        }
        dropNode();
        return lhs;
    }

    function parseMatchShape() : SamalShape {
        startNode();
        switch(current().getType()) {
            case Identifier:
                final varName = eat(Identifier).getSubstr();
                if(current().getType() == LCurly) {
                    // enum variant match
                    final fields = parseList(LCurly, Comma, RCurly, function() {
                        final fieldName = eat(Identifier).getSubstr();
                        eat(Colons);
                        final value = parseMatchShape();
                        return SamalShapeEnumVariantField.create(fieldName, value);
                    });
                    return SamalShapeEnumVariant.create(makeSourceRef(), varName, fields);
                }
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
            case Integer:
                var val = current().getSubstr();
                eat(TokenType.Integer);
                var valAsInt = Std.parseInt(val);
                if(valAsInt == null) {
                    throw new Exception(current().info() + " Couldn't convert " + val + " to int");
                }
                return SamalLiteralIntExpression.create(makeSourceRef(), valAsInt);

            case ByteLiteral:
                var val = current().getSubstr();
                val = val.substr(0, val.length - 1); // remove trailing 'b'
                eat(ByteLiteral);
                var valAsInt = Std.parseInt(val);
                if(valAsInt == null) {
                    throw new Exception(current().info() + " Couldn't convert " + val + " to byte");
                }
                return SamalLiteralByteExpression.create(makeSourceRef(), valAsInt);

            case LCurly:
                final scope = parseScope();
                return SamalScopeExpression.create(makeSourceRef(), scope);
            
            case LParen:
                final l = parseList(LParen, Comma, RParen, function() {
                    return parseExpression();
                });
                if(l.length == 1) {
                    // just a bracketet expression, used for precendence; you can't create tuples with just one element in samal :c
                    dropNode();
                    return l[0].sure();
                }
                return SamalCreateTupleExpression.create(makeSourceRef(), l);
            
            case Identifier:
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
                final ident = parseIdentifierWithTemplate();
                return SamalLoadIdentifierExpression.create(makeSourceRef(), ident);
            case If:
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
                if (peek().getType() == Colons) {
                    eat(LSquare);
                    eat(Colons);
                    var type = parseDatatype();
                    eat(RSquare);
                    return SamalCreateListExpression.createFull(makeSourceRef(), List(type), []);
                }
                var expressions = parseExpressionList(LSquare, RSquare);
                return SamalCreateListExpression.create(makeSourceRef(), expressions);

            case Match:
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
                eat(Fn);
                final params = parseFunctionParameterList();
                eat(RightArrow);
                final returnType = parseDatatype();
                final body = parseScope();
                return SamalCreateLambdaExpression.create(makeSourceRef(), params, returnType, body, []);

            case CharLiteral:
                final ch = eat(CharLiteral).getSubstr();
                return SamalLiteralCharExpression.create(makeSourceRef(), ch);
            
            case StringLiteral:
                final str = eat(StringLiteral).getSubstr();
                final listElements : Array<SamalExpression> = [];
                for(i in 0...str.length) {
                    listElements.push(SamalLiteralCharExpression.create(makeSourceRefNonDestructive(), str.charAt(i)));
                }
                return SamalCreateListExpression.createFull(makeSourceRef(), List(Char), listElements);

            case True:
                eat(True);
                return SamalLiteralBoolExpression.create(makeSourceRef(), true);

            case False:
                eat(False);
                return SamalLiteralBoolExpression.create(makeSourceRef(), false);

            case At:
                eat(At);
                final type = eat(Identifier).getSubstr();
                switch(type) {
                    case "start_native":
                        eat(LParen);
                        final returnName = eat(Identifier).getSubstr();
                        eat(RParen);

                        while(current().getType() != At && peek().getType() != Identifier) {
                            eat(current().getType());
                        }

                        eat(At);
                        final subMacroType = eat(Identifier).getSubstr();


                    default:
                        throw new Exception("Unknown compiler macro @" + type);
                }

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

    function currentWithoutNewlines() : Token {
        mTokenizer.push();
        skipNewlines();
        final tok = mTokenizer.current();
        mTokenizer.pop();
        return tok;
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
        final ret = SourceCodeRef.merge(base, mTokenizer.peek(-1).getSourceRef(), mTokenizer.getOriginalString());
        return ret;
    }
}