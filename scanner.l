%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

#include "expr_value.h"
#include "symbol_table.h"
#include "function_table.h"
#include "y.tab.h" // for token return by yacc

#define MAX_LINE_LENG 256
#define MAX_ID_LEN 64
#define MAX_SYMBOLS 1000
#define HASH_SIZE 211

#define LIST strcat(buf, yytext)

// Print macros
#define token(t, s) {LIST; /*printf("<%s: %s>\n", t, s);*/}
#define tokenInteger(t, s) {LIST; /*printf("<%s: %s>\n", t, s);*/}
#define tokenString(t, s) {LIST; /*printf("<%s: %s>\n", t, s);*/}
#define tokenOp(t, s) {LIST; /*printf("<%s: '%s'>\n", t, s);*/}
#define tokenDelim(t, s) {LIST; /*printf("<%s: '%s'>\n", t, s);*/}

int linenum = 1;
char buf[MAX_LINE_LENG];

%}

%option noyywrap
%x COMMENT

KEYWORD bool|break|case|char|const|continue|default|do|double|else|extern|false|float|for|foreach|if|int|main|print|println|read|return|string|switch|true|void|while
ID [a-zA-Z_][a-zA-Z0-9_]*
INT [0-9]+
REAL [-+]?([0-9]+\.[0-9]*([eE][-+]?[0-9]+)?|[0-9]+[eE][-+]?[0-9]+)
STRING \"([^\"\n]|\"\")*?\"
OP \+\+|\+|--|-|\*|\/|%|==|!=|<=|>=|=|<|>|\|\||&&|!
DELIM [\(\)\[\]\{\},.:;]

%%
"//".*"\n" {    // single line comment
    printf("Line%d: %s", linenum, yytext);
    linenum++;
    buf[0] = '\0';
}

"/*" {      // multi line comment
    BEGIN(COMMENT);
    buf[0] = '\0'; // clear buffer
}

<COMMENT>{
    "*/" {
        if (buf[0] != '\0') {
            printf("Line%d: %s\n", linenum, buf); // last line of comment
        }
        BEGIN(INITIAL);
        buf[0] = '\0';
    }
    \n {
        linenum++;
        if (buf[0] != '\0') {
            printf("Line%d: %s\n", linenum - 1, buf); // print comment
        }
        buf[0] = '\0';
    }
    . {
        LIST; // add to buffer
    }
}

{REAL}             {    //TODO: deal with exponent and sign
                    tokenString("REAL", yytext);
                    yylval.realval = atof(yytext);
                    return REAL;
                    }
{INT}              {
                    tokenInteger("INT", yytext);
                    yylval.intval = atoi(yytext);
                    return INT;
                    }
{STRING}           {
                    tokenString("STRING", yytext);
                    yylval.text = strdup(yytext);
                    return STRING;
                    }
{KEYWORD}          {token("KEYWORD", yytext); 
                    if (strcmp(yytext, "bool") == 0) { yylval.string = strdup(yytext); return KW_BOOL; }
                    if (strcmp(yytext, "break") == 0) { yylval.string = strdup(yytext); return KW_BREAK; }
                    if (strcmp(yytext, "case") == 0) { yylval.string = strdup(yytext); return KW_CASE; }
                    if (strcmp(yytext, "char") == 0) { yylval.string = strdup(yytext); return KW_CHAR; }
                    if (strcmp(yytext, "const") == 0) { yylval.string = strdup(yytext); return KW_CONST; }
                    if (strcmp(yytext, "continue") == 0) { yylval.string = strdup(yytext); return KW_CONTINUE; }
                    if (strcmp(yytext, "default") == 0) { yylval.string = strdup(yytext); return KW_DEFAULT; }
                    if (strcmp(yytext, "do") == 0) { yylval.string = strdup(yytext); return KW_DO; }
                    if (strcmp(yytext, "double") == 0) { yylval.string = strdup(yytext); return KW_DOUBLE; }
                    if (strcmp(yytext, "else") == 0) { yylval.string = strdup(yytext); return KW_ELSE; }
                    if (strcmp(yytext, "extern") == 0) { yylval.string = strdup(yytext); return KW_EXTERN; }
                    if (strcmp(yytext, "false") == 0) { yylval.boolval = false; return BOOL; }
                    if (strcmp(yytext, "float") == 0) { yylval.string = strdup(yytext); return KW_FLOAT; }
                    if (strcmp(yytext, "for") == 0) { yylval.string = strdup(yytext); return KW_FOR; }
                    if (strcmp(yytext, "foreach") == 0) { yylval.string = strdup(yytext); return KW_FOREACH; }
                    if (strcmp(yytext, "if") == 0) { yylval.string = strdup(yytext); return KW_IF; }
                    if (strcmp(yytext, "int") == 0) { yylval.string = strdup(yytext); return KW_INT; }
                    if (strcmp(yytext, "main") == 0) { yylval.string = strdup(yytext); return KW_MAIN; }
                    if (strcmp(yytext, "print") == 0) { yylval.string = strdup(yytext); return KW_PRINT; }
                    if (strcmp(yytext, "println") == 0) { yylval.string = strdup(yytext); return KW_PRINTLN; }
                    if (strcmp(yytext, "read") == 0) { yylval.string = strdup(yytext); return KW_READ; }
                    if (strcmp(yytext, "return") == 0) { yylval.string = strdup(yytext); return KW_RETURN; }
                    if (strcmp(yytext, "string") == 0) { yylval.string = strdup(yytext); return KW_STRING; }
                    if (strcmp(yytext, "switch") == 0) { yylval.string = strdup(yytext); return KW_SWITCH; }
                    if (strcmp(yytext, "true") == 0) { yylval.boolval = true; return BOOL; }
                    if (strcmp(yytext, "void") == 0) { yylval.string = strdup(yytext); return KW_VOID; }
                    if (strcmp(yytext, "while") == 0) { yylval.string = strdup(yytext); return KW_WHILE; }
                    }
{ID}               {
                    tokenString("ID", yytext); 
                    yylval.text = strdup(yytext);
                    return ID;
                    }
{OP}               {
                    tokenOp("OP", yytext);
                    if (strcmp(yytext, "++") == 0) { yylval.string = strdup(yytext); return OP_INC; }
                    if (strcmp(yytext, "+") == 0) { yylval.string = strdup(yytext); return OP_ADD; }
                    if (strcmp(yytext, "--") == 0) { yylval.string = strdup(yytext); return OP_DEC; }
                    if (strcmp(yytext, "-") == 0) { yylval.string = strdup(yytext); return OP_SUB; }
                    if (strcmp(yytext, "*") == 0) { yylval.string = strdup(yytext); return OP_MUL; }
                    if (strcmp(yytext, "/") == 0) { yylval.string = strdup(yytext); return OP_DIV; }
                    if (strcmp(yytext, "%") == 0) { yylval.string = strdup(yytext); return OP_MOD; }
                    if (strcmp(yytext, "==") == 0) { yylval.string = strdup(yytext); return OP_EQ; }
                    if (strcmp(yytext, "!=") == 0) { yylval.string = strdup(yytext); return OP_NEQ; }
                    if (strcmp(yytext, "<=") == 0) { yylval.string = strdup(yytext); return OP_LEQ; }
                    if (strcmp(yytext, ">=") == 0) { yylval.string = strdup(yytext); return OP_GEQ; }
                    if (strcmp(yytext, "=") == 0) { yylval.string = strdup(yytext); return OP_ASSIGN; }
                    if (strcmp(yytext, "<") == 0) { yylval.string = strdup(yytext); return OP_LT; }
                    if (strcmp(yytext, ">") == 0) { yylval.string = strdup(yytext); return OP_GT; }
                    if (strcmp(yytext, "||") == 0) { yylval.string = strdup(yytext); return OP_OR; }
                    if (strcmp(yytext, "&&") == 0) { yylval.string = strdup(yytext); return OP_AND; }
                    if (strcmp(yytext, "!") == 0) { yylval.string = strdup(yytext); return OP_NOT; }
                    }
{DELIM}            {
                    tokenDelim("DELIM", yytext);
                    if (strcmp(yytext, "(") == 0) { yylval.string = strdup(yytext); return DELIM_LPAR; }
                    if (strcmp(yytext, ")") == 0) { yylval.string = strdup(yytext); return DELIM_RPAR; }
                    if (strcmp(yytext, "[") == 0) { yylval.string = strdup(yytext); return DELIM_LBRACK; }
                    if (strcmp(yytext, "]") == 0) { yylval.string = strdup(yytext); return DELIM_RBRACK; }
                    if (strcmp(yytext, "{") == 0) { yylval.string = strdup(yytext); return DELIM_LBRACE; }
                    if (strcmp(yytext, "}") == 0) { yylval.string = strdup(yytext); return DELIM_RBRACE; }
                    if (strcmp(yytext, ",") == 0) { yylval.string = strdup(yytext); return DELIM_COMMA; }
                    if (strcmp(yytext, ".") == 0) { yylval.string = strdup(yytext); return DELIM_DOT; }
                    if (strcmp(yytext, ":") == 0) { yylval.string = strdup(yytext); return DELIM_COLON; }
                    if (strcmp(yytext, ";") == 0) { yylval.string = strdup(yytext); return DELIM_SEMICOLON; }
                    }
[ \t\r]+           ;    // ignore whitespace
\n                 {linenum++;} // increment line number
.                  {fprintf(stderr, "Unknown character: '%s'\n", yytext); exit(1);}
%%

// int main(int argc, char **argv) {
//     create();
//     yyin = fopen(argv[1], "r");
//     if (yyin == NULL) {
//         fprintf(stderr, "Error opening file: %s\n", argv[1]);
//         return 1;
//     }
//     yylex();
//     dump();
//     fclose(yyin);
//     return 0;
// }