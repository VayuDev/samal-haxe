package tests;

import samal.Tokenizer;
import buddy.BuddySuite;
using buddy.Should;

class TokenizerTests extends BuddySuite
{
    public function new() {
        describe("Tokenizer", {
            it("Should return TokenType.Invalid on empty", {
                var t = new Tokenizer("");
                t.current().getType().should().equal(TokenType.Invalid);
            });
            it("Should tokenize simple stuff correctly", {
                var t = new Tokenizer("a + b ->{03 - -22 if");
                t.current().getType().should().equal(TokenType.Identifier);
                t.current().getSubstr().should().be("a");
                t.next();
                t.current().getType().should().equal(TokenType.Plus);
                t.current().getSubstr().should().be("+");
                t.next();
                t.current().getType().should().equal(TokenType.Identifier);
                t.current().getSubstr().should().be("b");
                t.next();
                t.current().getType().should().equal(TokenType.RightArrow);
                t.current().getSubstr().should().be("->");
                t.next();
                t.current().getType().should().equal(TokenType.LCurly);
                t.current().getSubstr().should().be("{");
                t.next();
                t.current().getType().should().equal(TokenType.Integer);
                t.current().getSubstr().should().be("03");
                t.next();
                t.current().getType().should().equal(TokenType.Minus);
                t.current().getSubstr().should().be("-");
                t.next();
                t.current().getType().should().equal(TokenType.Integer);
                t.current().getSubstr().should().be("-22");
                t.next();
                t.current().getType().should().equal(TokenType.If);
                t.current().getSubstr().should().be("if");
                t.next();
                t.current().getType().should().equal(TokenType.Invalid);
                t.next();
            });
        });
    }
}