package samal.bootstrap;

import samal.bootstrap.BootstrapUtils;
import haxe.Exception;
import haxe.ds.GenericStack;

class SourceCodeRef {
    private var lineStart : Int;
    private var lineEnd : Int;
    private var columnStart : Int;
    private var columnEnd : Int;
    private var substr : String;
    private var indexStart : Int;
    private var indexEnd : Int;
    public function new(lineStart : Int, lineEnd : Int, columnStart : Int, columnEnd : Int, indexStart : Int, indexEnd : Int, substr : String) {
        this.lineStart = lineStart;
        this.lineEnd = lineEnd;
        this.columnStart = columnStart;
        this.columnEnd = columnEnd;
        this.indexStart = indexStart;
        this.indexEnd = indexEnd;
        this.substr = substr;
    }
    public function info() : String {
        return "[" + lineStart + ":" + columnStart + "] '" + BootstrapUtils.escapeString(substr) + "'";
    }
    public function errorInfo() : String {
        return "At [" + lineStart + ":" + columnStart + "]:\n" + substr;
    }
    public static function merge(first : SourceCodeRef, last : SourceCodeRef, originalString : String) {
        return new SourceCodeRef(first.lineStart, last.lineEnd, first.columnStart, last.columnEnd, first.indexStart, last.indexEnd, originalString.substring(first.indexStart, last.indexEnd));
    }
    public function getSubstr() {
        return substr;
    }
    public function getStartIndex() {
        return indexStart;
    }
}

enum TokenType {
    Invalid;
    Unknown;
    Plus;
    Minus;
    LCurly;
    RCurly;
    LParen;
    RParen;
    Identifier;
    Equals;
    Less;
    More;
    LessEqual;
    MoreEqual;
    LSquare;
    RSquare;
    NewLine;
    Colons;
    Comma;
    At;
    Dollar;
    Underscore;
    ExclamationMark;
    Dot;
    Star;
    Slash;
    RightArrow;
    DoubleEquals;
    NotEquals;
    Integer;
    Pipe;
    FunctionChain;
    StringLiteral;
    CharLiteral;
    If;
    Fn;
    Match;
    Else;
    Bool;
    Int;
    DoubleAnd;
    DoublePipe;
    Module;
    Struct;
    Hashtag;
    Enum;
}


class Token {
    private var type : TokenType;
    private var ref : SourceCodeRef;
    private var skippedSpaces : Int;
    public function new(ref : SourceCodeRef, type : TokenType, skippedSpaces : Int) {
        this.type = type;
        this.ref = ref;
        this.skippedSpaces = skippedSpaces;
    }
    public function getType() : TokenType {
        return type;
    }
    public function info() : String {
        var ret = type.getName();
        ret += ": ";
        ret += ref.info();
        return ret;
    }
    public function getSourceRef() : SourceCodeRef {
        return ref;
    }
    public function getSubstr() : String {
        return ref.getSubstr();
    }
    public function getSkippedWhitespaces() : Int {
        return skippedSpaces;
    }
}

enum TokenizerMode {
    Normal;
    DisableMulticharRecognition;
}

@:nullSafety(Off)
class Tokenizer {
    var tokens : Array<Token>;
    var indexStack = new GenericStack<Int>();
    var origianlString : String;

    public function new(code : String, mode : TokenizerMode) {
        var generator = new TokenGenerator(code, mode);
        tokens = generator.getTokens();
        indexStack.add(0);
        this.origianlString = code;    
    }

    public function current() : Token {
        if(indexStack.first() >= tokens.length) {
            if(tokens.length == 0) {
                return new Token(new SourceCodeRef(1, 1, 1, 1, 0, 0, ""), TokenType.Invalid, 0);
            }
            return new Token(tokens[tokens.length - 1].getSourceRef(), TokenType.Invalid, 0);
        }
        return tokens[indexStack.first()];
    }
    public function peek(n : Int = 1) : Token {
        if(indexStack.first() + n >= tokens.length) {
            if(tokens.length == 0) {
                return new Token(new SourceCodeRef(1, 1, 1, 1, 0, 0, ""), TokenType.Invalid, 0);
            }
            return new Token(tokens[tokens.length - 1].getSourceRef(), TokenType.Invalid, 0);
        }
        return tokens[indexStack.first() + n];
    }
    public function next() : Void {
        indexStack.add(indexStack.pop() + 1);
    }
    public function push() : Void {
        indexStack.add(indexStack.first());
    }
    public function pop() : Void {
        indexStack.pop();
    }
    public function acceptState() : Void {
        var top = indexStack.first();
        indexStack.pop();
        indexStack.pop();
        indexStack.add(top);
    }
    public function eat(type : TokenType) : Void {
        if(current().getType() != type && CompileConfig.get().shouldThrowErrors()) {
            throw new Exception(current().info() + ": Expected " + type.getName());
        }
        next();
    }
    public function getOriginalString() : String {
        return origianlString;
    }
    public function skipNewlines() {
        while(current().getType() == NewLine) {
            eat(NewLine);
        }
    }
    public function acceptAndGetSubstring() : String {
        final end = indexStack.pop();
        final start = indexStack.pop();
        indexStack.add(end);
        return origianlString.substring(
            tokens[start].getSourceRef().getStartIndex(), 
            tokens[end].getSourceRef().getStartIndex());
    }
}

class TokenGenerator {
    var code : String;
    var index : Int = 0;
    var line : Int = 1;
    var column : Int = 1;
    var indexStart : Int = -1;
    var lineStart : Int = -1;
    var columnStart : Int = -1;
    var tokens : Array<Token> = new Array();
    var skippedSpaces : Int = 0;

    static final SINGLE_CHAR_TOKENS = [
        '+' => TokenType.Plus,
        '<' => TokenType.Less,
        '>' => TokenType.More,
        '-' => TokenType.Minus,
        '=' => TokenType.Equals,
        '{' => TokenType.LCurly,
        '}' => TokenType.RCurly,
        "\n" => TokenType.NewLine,
        '[' => TokenType.LSquare,
        ']' => TokenType.RSquare,
        '(' => TokenType.LParen,
        ')' => TokenType.RParen,
        ':' => TokenType.Colons,
        ',' => TokenType.Comma,
        '@' => TokenType.At,
        '$' => TokenType.Dollar,
        '_' => TokenType.Underscore,
        '!' => TokenType.ExclamationMark,
        '.' => TokenType.Dot,
        '*' => TokenType.Star,
        '/' => TokenType.Slash,
        "|" => TokenType.Pipe,
        "#" => TokenType.Hashtag
    ];

    static final MULTI_CHAR_TOKENS = [
        "<=" => TokenType.LessEqual,
        ">=" => TokenType.MoreEqual,
        "->" => TokenType.RightArrow,
        "==" => TokenType.DoubleEquals,
        "!=" => TokenType.NotEquals,
        "|>" => TokenType.FunctionChain,
        "if" => TokenType.If,
        "fn" => TokenType.Fn,
        "match" => TokenType.Match,
        "else" => TokenType.Else,
        "bool" => TokenType.Bool,
        "int" => TokenType.Int,
        "&&" => TokenType.DoubleAnd,
        "||" => TokenType.DoublePipe,
        "module" => TokenType.Module,
        "struct" => TokenType.Struct,
        "enum" => TokenType.Enum
    ];
    

    public function new(code : String, mode : TokenizerMode) {
        this.code = code;
        while(index < code.length) {
            skippedSpaces = 0;
            skipWhitespaces();
            lineStart = line;
            columnStart = column;
            indexStart = index;
            
            if(mode != TokenizerMode.DisableMulticharRecognition) {
                var isMultiCharToken = false;
                for(str => type in MULTI_CHAR_TOKENS.keyValueIterator()) {
                    if(str == getNChars(str.length)) {
                        isMultiCharToken = true;
                        for(_ in 0...str.length) {
                            advance();
                        }
                        tokens.push(new Token(makeSourceRef(), type, skippedSpaces));
                        break;
                    }
                }
                if(isMultiCharToken) {
                    continue;
                }
            }
            
            var isInteger = false;
            if(getCurrentChar() == "-" && StringTools.contains("0123456789", getNextChar())) {
                advance();
                isInteger = true;
            } else if(StringTools.contains("0123456789", getCurrentChar())) {
                isInteger = true;
            }
            if(isInteger) {

                while(getCurrentChar() != "" && "0123456789".indexOf(getCurrentChar()) != -1) {
                    advance();
                }
                tokens.push(new Token(makeSourceRef(), TokenType.Integer, skippedSpaces));
                continue;
            }

            var tok = SINGLE_CHAR_TOKENS.get(getCurrentChar());
            if(tok != null) {
                genSingleCharToken(tok);
                continue;
            }
            var isIdentifier = false;
            while(getCurrentChar() != "" && "abcdefghijklmnopqrstuvwyxzABCDEFGHIJKLMNOPQRSTUVWXYZ._".indexOf(getCurrentChar()) != -1) {
                advance();
                isIdentifier = true;
            }
            if(isIdentifier) {
                tokens.push(new Token(makeSourceRef(), TokenType.Identifier, skippedSpaces));
                continue;
            }

            if(getCurrentChar() == "\"") {
                var res = "";
                advance();
                while(true) {
                    if(getCurrentChar() == "\"") {
                        break;
                    } else if(getCurrentChar() == "\\" && getNextChar() == "\"") {
                        advance();
                    }
                    res += getCurrentChar();
                    advance();
                }
                advance();
                tokens.push(new Token(new SourceCodeRef(lineStart, line, columnStart, column, indexStart, index, res), TokenType.StringLiteral, skippedSpaces));
                continue;
            }

            if(getCurrentChar() == "\'") {
                advance();
                var ch : String = "";
                if(getCurrentChar() == "\\") {
                    advance();
                    switch(getCurrentChar()) {
                        case "n":
                            ch = "\n";
                        case "r":
                            ch = "\r";
                        case "'":
                            ch = "\'";
                        case "0":
                            ch = "\u{0}";
                        case _:
                            throwException("Unknown escape sequence with " + getCurrentChar());
                    }
                } else {
                    ch = getCurrentChar();
                }
                advance();
                if(getCurrentChar() != "\'") {
                    throwException("String literals should only contain one character!");
                }
                advance();
                tokens.push(new Token(new SourceCodeRef(lineStart, line, columnStart, column, indexStart, index, ch), TokenType.CharLiteral, skippedSpaces));
                continue;
            }
            advance();
            tokens.push(new Token(makeSourceRef(), TokenType.Unknown, skippedSpaces));
        }
    }

    private function throwException(msg : String) {
        throw new Exception("Tokenizer : [" + line + ":" + column + "] " + msg);
    }

    public function getTokens() : Array<Token> {
        return tokens;
    }

    private function genSingleCharToken(type : TokenType) {
        advance();
        tokens.push(new Token(makeSourceRef(), type, skippedSpaces));
        skippedSpaces = 0;
    }

    private function makeSourceRef() : SourceCodeRef {
        return new SourceCodeRef(lineStart, line, columnStart, column, indexStart, index, code.substring(indexStart, index));
    }

    private function getCurrentChar() : String {
        return code.charAt(index);
    }

    private function getNextChar() : String {
        return code.charAt(index + 1);
    }

    private function getNChars(n : Int) : String {
        return code.substr(index, n);
    }

    private function advance() {
        if(getCurrentChar() == "\n") {
            line += 1;
            column = 1;
        } else {
            column += 1;
        }
        if(" \t\r".indexOf(getCurrentChar()) != -1) {
            skippedSpaces += 1;
        }
        index += 1;
    }

    private function skipWhitespaces() {
        while(" \t\r".indexOf(getCurrentChar()) != -1) {
            advance();
        }
    }
}