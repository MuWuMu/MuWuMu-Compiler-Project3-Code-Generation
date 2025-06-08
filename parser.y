%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>

#include "symbol_table.h"
#include "function_table.h"
#include "expr_value.h"

#include "code_generation.h"

// get token that recognized by scanner
extern int yylex();
extern int yyparse();
extern FILE *yyin;
extern char *yytext;
extern int linenum;

SymbolTable *currentTable = NULL;
FunctionTable *functionTable = NULL;

// Helper variables for function return type checking
char *current_function_name_for_return_check = NULL;
char *current_function_return_type_for_return_check = NULL; // Stores "int", "float", "void", etc.
bool non_void_function_has_return_value_statement = false; // True if a 'return <expr>;' was found and type-checked

// Helper function to create a default error expression value
static inline ExprValue default_expr_error_value() {
    ExprValue res;
    res.type = "ERROR"; 
    res.value = NULL;   
    return res;
}

void yyerror(const char *s) {
    fprintf(stderr, "Error at line %d: %s\n", linenum, s);
}

void yywarning(const char *s) {
    fprintf(stderr, "Warning at line %d: %s\n", linenum, s);
}


%}

%union {
    char *string;   // For type_specifier (int, float...)
    Node *node;     // For declarator_list and declarator_list_with_init
    int intval;     // For integer constants
    float realval;  // For real constants
    bool boolval;    // For boolean constants
    char *text;     // For string constants (ID, string...)
    Parameter *param ; // For function parameters
    ExprValue expr_val;
}

// define token
%token <string> KW_BOOL KW_BREAK KW_CASE KW_CHAR KW_CONST KW_CONTINUE KW_DEFAULT KW_DO KW_DOUBLE KW_ELSE KW_EXTERN KW_FLOAT KW_FOR KW_FOREACH KW_IF KW_INT KW_MAIN KW_PRINT KW_PRINTLN KW_READ KW_RETURN KW_STRING KW_SWITCH KW_VOID KW_WHILE
%token <text> ID
%token <intval> INT
%token <realval> REAL
%token <boolval> BOOL
%token <text> STRING
%token <string> OP_INC OP_ADD OP_DEC OP_SUB OP_MUL OP_DIV OP_MOD OP_EQ OP_NEQ OP_LEQ OP_GEQ OP_ASSIGN OP_LT OP_GT OP_OR OP_AND OP_NOT
%token <string> DELIM_LPAR DELIM_RPAR DELIM_LBRACK DELIM_RBRACK DELIM_LBRACE DELIM_RBRACE DELIM_COMMA DELIM_DOT DELIM_COLON DELIM_SEMICOLON

%type <string> type_specifier
%type <node> declarator_list
%type <expr_val> expression
%type <expr_val> arithmetic_expression
%type <param> parameter_list
%type <param> argument_list
%type <param> argument_list_actual
%type <expr_val> function_invocation

%left OP_OR
%left OP_AND
%right OP_NOT
%left OP_LT OP_LEQ OP_EQ OP_NEQ OP_GEQ OP_GT
%left OP_ADD OP_SUB
%left OP_MUL OP_DIV OP_MOD
%right OP_INC OP_DEC

%%

program:
    declaration program
    | function_declaration program
    | main_function 
    ;

main_function:
    KW_VOID KW_MAIN DELIM_LPAR DELIM_RPAR block
    ;

declaration:
    // single or multiple declaration
    type_specifier declarator_list DELIM_SEMICOLON {
        // printf("Declaration without initialization: type=%s\n", $1);    // for debugging

        // traverse declarator_list，insert each one into symbol table
        Node *current = $2;
        while (current != NULL) {
            if (lookupSymbolInCurrentTable(currentTable, current->name)) {
                yyerror("Duplicate declaration of variable");
            } else if (current->type != NULL) {
                // type check
                if (current->type == "INT" && $1 != "int") 
                    yyerror("Type mismatch in declaration");
                else if (current->type == "REAL" && $1 != "float" && $1 != "double")
                    yyerror("Type mismatch in declaration");
                else if (current->type == "BOOL" && $1 != "bool")
                    yyerror("Type mismatch in declaration");
                else if (current->type == "STRING" && $1 != "string" && $1 != "char")
                    yyerror("Type mismatch in declaration");
            } else {
                insertSymbol(currentTable, current->name, $1, 0);
            }
            current = current->next;
        }
    }
    // single or multi const declare
    | KW_CONST type_specifier declarator_list DELIM_SEMICOLON {
        // printf("Const declaration: type=%s\n", $2);   // for debugging

        Node *current = $3;
        while (current != NULL) {
            if (lookupSymbolInCurrentTable(currentTable, current->name)) {
                yyerror("Duplicate declaration of variable");
            } else if (current->type != NULL) {
                // type check
                if (current->type == "INT" && $2 != "int") 
                    yyerror("Type mismatch in declaration");
                else if (current->type == "REAL" && $2 != "float" && $2 != "double")
                    yyerror("Type mismatch in declaration");
                else if (current->type == "BOOL" && $2 != "bool")
                    yyerror("Type mismatch in declaration");
                else if (current->type == "STRING" && $2 != "string" && $2 != "char")
                    yyerror("Type mismatch in declaration");
            } else if (current->value == NULL) {
                yyerror("Const variable must be initialized");
            } else {
                insertSymbol(currentTable, current->name, $2, 1); // set as const
                // printf("Initialized const variable: %s with value\n", current->name);   // for debugging
            }
            current = current->next;
        }
    }
    ;
type_specifier:
    KW_INT { $$ = "int";}
    | KW_FLOAT { $$ = "float";}
    | KW_DOUBLE { $$ = "double";}
    | KW_CHAR { $$ = "char";}
    | KW_BOOL { $$ = "bool";}
    | KW_STRING { $$ = "string";}
    ;

declarator_list:
    ID {
        // single declaration without initialization
        $$ = (Node *)malloc(sizeof(Node));
        $$->name = strdup($1);
        $$->type = NULL; // no type yet
        $$->next = NULL;
        $$->value = NULL; // no initialization
    }
    | ID OP_ASSIGN expression {
        // single declaration with initialization
        $$ = (Node *)malloc(sizeof(Node));
        $$->name = strdup($1);
        $$->type = $3.type;
        $$->next = NULL;
        $$->value = $3.value; // initialization value
    }
    | ID DELIM_COMMA declarator_list {
        // multi declaration without initialization
        $$ = (Node *)malloc(sizeof(Node));
        $$->name = strdup($1);
        $$->type = $3->type;
        $$->next = $3;
        $$->value = NULL;
    }
    | ID OP_ASSIGN expression DELIM_COMMA declarator_list {
        // multi declaration with initialization
        $$ = (Node *)malloc(sizeof(Node));
        $$->name = strdup($1);
        $$->type = $3.type;
        $$->next = $5;
        $$->value = $3.value;
    }
    ;

arithmetic_expression:
    OP_SUB expression %prec OP_INC {
        // Unary minus
        if (strcmp($2.type, "INT") == 0) {
            $$.type = "INT";
            $$.value = malloc(sizeof(int));
            *(int *)$$.value = -(*(int *)$2.value);
        } else if (strcmp($2.type, "REAL") == 0) {
            $$.type = "REAL";
            $$.value = malloc(sizeof(float));
            *(float *)$$.value = -(*(float *)$2.value);
        } else {
            yyerror("Invalid type for unary minus");
            $$ = default_expr_error_value(); // Set to error value
        }
        if ($2.value) free($2.value); // Free operand value
    }
    | expression OP_INC {
        // Increment
        if (strcmp($1.type, "INT") == 0) {
            $$.type = "INT";
            $$.value = malloc(sizeof(int));
            *(int *)$$.value = (*(int *)$1.value) + 1;
        } else if (strcmp($1.type, "REAL") == 0) {
            $$.type = "REAL";
            $$.value = malloc(sizeof(float));
            *(float *)$$.value = (*(float *)$1.value) + 1.0;
        } else {
            yyerror("Invalid type for increment");
            $$ = default_expr_error_value(); // Set to error value
        }
        if ($1.value) free($1.value); // Free operand value
    }
    | expression OP_DEC {
        // Decrement
        if (strcmp($1.type, "INT") == 0) {
            $$.type = "INT";
            $$.value = malloc(sizeof(int));
            *(int *)$$.value = (*(int *)$1.value) - 1;
        } else if (strcmp($1.type, "REAL") == 0) {
            $$.type = "REAL";
            $$.value = malloc(sizeof(float));
            *(float *)$$.value = (*(float *)$1.value) - 1.0;
        } else {
            yyerror("Invalid type for decrement");
            $$ = default_expr_error_value(); // Set to error value
        }
        if ($1.value) free($1.value); // Free operand value
    }
    | expression OP_MUL expression {
        // Multiplication
        $$ = default_expr_error_value();
        bool mixed_types_numeric = false;
        if (strcmp($1.type, "INT") == 0 && strcmp($3.type, "INT") == 0) {
            $$.type = "INT";
            $$.value = malloc(sizeof(int));
            *(int *)$$.value = (*(int *)$1.value) * (*(int *)$3.value);
        } else if ((strcmp($1.type, "REAL") == 0 || strcmp($1.type, "INT") == 0) &&
                   (strcmp($3.type, "REAL") == 0 || strcmp($3.type, "INT") == 0)) {
            $$.type = "REAL";
            $$.value = malloc(sizeof(float));
            float val1 = (strcmp($1.type, "INT") == 0) ? (float)(*(int*)$1.value) : (*(float*)$1.value);
            float val2 = (strcmp($3.type, "INT") == 0) ? (float)(*(int*)$3.value) : (*(float*)$3.value);
            *(float *)$$.value = val1 * val2;

            if (strcmp($1.type, "INT") == 0 && strcmp($3.type, "REAL") == 0) {
                yywarning("Implicit conversion from int to real in addition (left operand).");
                mixed_types_numeric = true;
            } else if (strcmp($1.type, "REAL") == 0 && strcmp($3.type, "INT") == 0) {
                yywarning("Implicit conversion from int to real in addition (right operand).");
                mixed_types_numeric = true;
            }

        } else {
            yyerror("Type mismatch in multiplication");
        }
        if ($1.value) free($1.value); // Free operand values
        if ($3.value) free($3.value);
    }
    | expression OP_DIV expression {
        // Division
        $$ = default_expr_error_value();
        bool mixed_types_numeric = false;
        if (strcmp($1.type, "INT") == 0 && strcmp($3.type, "INT") == 0) {
            if (*(int *)$3.value == 0) {
                yyerror("Division by zero (integer)");
            } else {
                $$.type = "INT";
                $$.value = malloc(sizeof(int));
                *(int *)$$.value = (*(int *)$1.value) / (*(int *)$3.value);
            }
        } else if ((strcmp($1.type, "REAL") == 0 || strcmp($1.type, "INT") == 0) &&
                   (strcmp($3.type, "REAL") == 0 || strcmp($3.type, "INT") == 0)) {
            float val1 = (strcmp($1.type, "INT") == 0) ? (float)(*(int*)$1.value) : (*(float*)$1.value);
            float val2 = (strcmp($3.type, "INT") == 0) ? (float)(*(int*)$3.value) : (*(float*)$3.value);
            if (val2 == 0.0) {
                yyerror("Division by zero (float)");
            } else {
                $$.type = "REAL";
                $$.value = malloc(sizeof(float));
                *(float *)$$.value = val1 / val2;
            }

            if (strcmp($1.type, "INT") == 0 && strcmp($3.type, "REAL") == 0) {
                yywarning("Implicit conversion from int to real in addition (left operand).");
                mixed_types_numeric = true;
            } else if (strcmp($1.type, "REAL") == 0 && strcmp($3.type, "INT") == 0) {
                yywarning("Implicit conversion from int to real in addition (right operand).");
                mixed_types_numeric = true;
            }

        } else {
            yyerror("Type mismatch in division");
        }
        if ($1.value) free($1.value);
        if ($3.value) free($3.value);
    }
    | expression OP_MOD expression {
        // Modulus
        if (strcmp($1.type, "INT") == 0 && strcmp($3.type, "INT") == 0) {
            if (*(int *)$3.value == 0) {
                yyerror("Modulus by zero");
            } else {
                $$.type = "INT";
                $$.value = malloc(sizeof(int));
                *(int *)$$.value = (*(int *)$1.value) % (*(int *)$3.value);
            }
        } else {
            yyerror("Type mismatch in modulus");
        }
        if ($1.value) free($1.value);
        if ($3.value) free($3.value);
    }
    | expression OP_ADD expression {
        // Addition
        $$ = default_expr_error_value();
        bool mixed_types_numeric = false;
        if (strcmp($1.type, "INT") == 0 && strcmp($3.type, "INT") == 0) {
            $$.type = "INT";
            $$.value = malloc(sizeof(int));
            *(int *)$$.value = (*(int *)$1.value) + (*(int *)$3.value);
        } else if ((strcmp($1.type, "REAL") == 0 || strcmp($1.type, "INT") == 0) &&
                   (strcmp($3.type, "REAL") == 0 || strcmp($3.type, "INT") == 0)) {
            $$.type = "REAL";
            $$.value = malloc(sizeof(float));
            float left = (strcmp($1.type, "INT") == 0) ? (float)(*(int *)$1.value) : (*(float *)$1.value);
            float right = (strcmp($3.type, "INT") == 0) ? (float)(*(int *)$3.value) : (*(float *)$3.value);
            *(float *)$$.value = left + right;

            if (strcmp($1.type, "INT") == 0 && strcmp($3.type, "REAL") == 0) {
                yywarning("Implicit conversion from int to real in addition (left operand).");
                mixed_types_numeric = true;
            } else if (strcmp($1.type, "REAL") == 0 && strcmp($3.type, "INT") == 0) {
                yywarning("Implicit conversion from int to real in addition (right operand).");
                mixed_types_numeric = true;
            }

        } else if (strcmp($1.type, "STRING") == 0 && strcmp($3.type, "STRING") == 0) {
            // String concatenation
            $$.type = "STRING";
            char *s1 = (char*)$1.value;
            char *s2 = (char*)$3.value;
            $$.value = malloc(strlen(s1) + strlen(s2) + 1);
            strcpy((char*)$$.value, s1);
            strcat((char*)$$.value, s2);
        }
         else {
            yyerror("Type mismatch in addition");
        }
        if ($1.value) free($1.value);
        if ($3.value) free($3.value);
    }
    | expression OP_SUB expression {
        // Subtraction
        $$ = default_expr_error_value();
        bool mixed_types_numeric = false;
        if (strcmp($1.type, "INT") == 0 && strcmp($3.type, "INT") == 0) {
            $$.type = "INT";
            $$.value = malloc(sizeof(int));
            *(int *)$$.value = (*(int *)$1.value) - (*(int *)$3.value);
        } else if ((strcmp($1.type, "REAL") == 0 || strcmp($1.type, "INT") == 0) &&
                   (strcmp($3.type, "REAL") == 0 || strcmp($3.type, "INT") == 0)) {
            $$.type = "REAL";
            $$.value = malloc(sizeof(float));
            float val1 = (strcmp($1.type, "INT") == 0) ? (float)(*(int*)$1.value) : (*(float*)$1.value);
            float val2 = (strcmp($3.type, "INT") == 0) ? (float)(*(int*)$3.value) : (*(float*)$3.value);
            *(float *)$$.value = val1 - val2;

            if (strcmp($1.type, "INT") == 0 && strcmp($3.type, "REAL") == 0) {
                yywarning("Implicit conversion from int to real in addition (left operand).");
                mixed_types_numeric = true;
            } else if (strcmp($1.type, "REAL") == 0 && strcmp($3.type, "INT") == 0) {
                yywarning("Implicit conversion from int to real in addition (right operand).");
                mixed_types_numeric = true;
            }
            
        } else {
            yyerror("Type mismatch in subtraction");
        }
        if ($1.value) free($1.value);
        if ($3.value) free($3.value);
    }
    | expression OP_LT expression {
        // Less than
        $$ = default_expr_error_value();
        $$.type = "BOOL"; // Result is always BOOL
        $$.value = malloc(sizeof(bool));
        if ((strcmp($1.type, "INT") == 0 || strcmp($1.type, "REAL") == 0) &&
            (strcmp($3.type, "INT") == 0 || strcmp($3.type, "REAL") == 0)) {
            // Warning
            if (strcmp($1.type, "INT") == 0 && strcmp($3.type, "REAL") == 0) {
                yywarning("Implicit conversion from int to real in addition (left operand).");
            } else if (strcmp($1.type, "REAL") == 0 && strcmp($3.type, "INT") == 0) {
                yywarning("Implicit conversion from int to real in addition (right operand).");
            }
            float val1 = (strcmp($1.type, "INT") == 0) ? (float)(*(int*)$1.value) : (*(float*)$1.value);
            float val2 = (strcmp($3.type, "INT") == 0) ? (float)(*(int*)$3.value) : (*(float*)$3.value);
            *(bool *)$$.value = val1 < val2;
        } else if (strcmp($1.type, "STRING") == 0 && strcmp($3.type, "STRING") == 0) {
             *(bool *)$$.value = strcmp((char*)$1.value, (char*)$3.value) < 0;
        }
        else {
            yyerror("Type mismatch in less than comparison");
            *(bool *)$$.value = false; // Default on error
        }
        if ($1.value) free($1.value);
        if ($3.value) free($3.value);
    }
    | expression OP_LEQ expression {
        // Less than or equal to
        $$ = default_expr_error_value();
        $$.type = "BOOL"; // Result is always BOOL
        $$.value = malloc(sizeof(bool));
        if ((strcmp($1.type, "INT") == 0 || strcmp($1.type, "REAL") == 0) &&
            (strcmp($3.type, "INT") == 0 || strcmp($3.type, "REAL") == 0)) {
            // Warning
            if (strcmp($1.type, "INT") == 0 && strcmp($3.type, "REAL") == 0) {
                yywarning("Implicit conversion from int to real in addition (left operand).");
            } else if (strcmp($1.type, "REAL") == 0 && strcmp($3.type, "INT") == 0) {
                yywarning("Implicit conversion from int to real in addition (right operand).");
            }
            float val1 = (strcmp($1.type, "INT") == 0) ? (float)(*(int*)$1.value) : (*(float*)$1.value);
            float val2 = (strcmp($3.type, "INT") == 0) ? (float)(*(int*)$3.value) : (*(float*)$3.value);
            *(bool *)$$.value = val1 <= val2;
        } else if (strcmp($1.type, "STRING") == 0 && strcmp($3.type, "STRING") == 0) {
             *(bool *)$$.value = strcmp((char*)$1.value, (char*)$3.value) <= 0;
        }
        else {
            yyerror("Type mismatch in less equal comparison");
            *(bool *)$$.value = false; // Default on error
        }
        if ($1.value) free($1.value);
        if ($3.value) free($3.value);
    }
    | expression OP_EQ expression {
        // Equal to
        $$ = default_expr_error_value();
        $$.type = "BOOL"; // Result is always BOOL
        $$.value = malloc(sizeof(bool));
        if ((strcmp($1.type, "INT") == 0 || strcmp($1.type, "REAL") == 0) &&
            (strcmp($3.type, "INT") == 0 || strcmp($3.type, "REAL") == 0)) {
            // Warning
            if (strcmp($1.type, "INT") == 0 && strcmp($3.type, "REAL") == 0) {
                yywarning("Implicit conversion from int to real in addition (left operand).");
            } else if (strcmp($1.type, "REAL") == 0 && strcmp($3.type, "INT") == 0) {
                yywarning("Implicit conversion from int to real in addition (right operand).");
            }
            float val1 = (strcmp($1.type, "INT") == 0) ? (float)(*(int*)$1.value) : (*(float*)$1.value);
            float val2 = (strcmp($3.type, "INT") == 0) ? (float)(*(int*)$3.value) : (*(float*)$3.value);
            *(bool *)$$.value = val1 == val2;
        } else if (strcmp($1.type, "STRING") == 0 && strcmp($3.type, "STRING") == 0) {
             *(bool *)$$.value = strcmp((char*)$1.value, (char*)$3.value) == 0;
        }
        else {
            yyerror("Type mismatch in equal comparison");
            *(bool *)$$.value = false; // Default on error
        }
        if ($1.value) free($1.value);
        if ($3.value) free($3.value);
    }
    | expression OP_GEQ expression {
        // Greater than or equal to
        $$ = default_expr_error_value();
        $$.type = "BOOL"; // Result is always BOOL
        $$.value = malloc(sizeof(bool));
        if ((strcmp($1.type, "INT") == 0 || strcmp($1.type, "REAL") == 0) &&
            (strcmp($3.type, "INT") == 0 || strcmp($3.type, "REAL") == 0)) {
            // Warning
            if (strcmp($1.type, "INT") == 0 && strcmp($3.type, "REAL") == 0) {
                yywarning("Implicit conversion from int to real in addition (left operand).");
            } else if (strcmp($1.type, "REAL") == 0 && strcmp($3.type, "INT") == 0) {
                yywarning("Implicit conversion from int to real in addition (right operand).");
            }
            float val1 = (strcmp($1.type, "INT") == 0) ? (float)(*(int*)$1.value) : (*(float*)$1.value);
            float val2 = (strcmp($3.type, "INT") == 0) ? (float)(*(int*)$3.value) : (*(float*)$3.value);
            *(bool *)$$.value = val1 >= val2;
        } else if (strcmp($1.type, "STRING") == 0 && strcmp($3.type, "STRING") == 0) {
             *(bool *)$$.value = strcmp((char*)$1.value, (char*)$3.value) >= 0;
        }
        else {
            yyerror("Type mismatch in greater equal comparison");
            *(bool *)$$.value = false; // Default on error
        }
        if ($1.value) free($1.value);
        if ($3.value) free($3.value);
    }
    | expression OP_GT expression {
        // Greater than
        $$ = default_expr_error_value();
        $$.type = "BOOL"; // Result is always BOOL
        $$.value = malloc(sizeof(bool));
        if ((strcmp($1.type, "INT") == 0 || strcmp($1.type, "REAL") == 0) &&
            (strcmp($3.type, "INT") == 0 || strcmp($3.type, "REAL") == 0)) {
            // Warning
            if (strcmp($1.type, "INT") == 0 && strcmp($3.type, "REAL") == 0) {
                yywarning("Implicit conversion from int to real in addition (left operand).");
            } else if (strcmp($1.type, "REAL") == 0 && strcmp($3.type, "INT") == 0) {
                yywarning("Implicit conversion from int to real in addition (right operand).");
            }
            float val1 = (strcmp($1.type, "INT") == 0) ? (float)(*(int*)$1.value) : (*(float*)$1.value);
            float val2 = (strcmp($3.type, "INT") == 0) ? (float)(*(int*)$3.value) : (*(float*)$3.value);
            *(bool *)$$.value = val1 > val2;
        } else if (strcmp($1.type, "STRING") == 0 && strcmp($3.type, "STRING") == 0) {
             *(bool *)$$.value = strcmp((char*)$1.value, (char*)$3.value) > 0;
        }
        else {
            yyerror("Type mismatch in greater than comparison");
            *(bool *)$$.value = false; // Default on error
        }
        if ($1.value) free($1.value);
        if ($3.value) free($3.value);
    }
    | expression OP_NEQ expression {
        // Not equal to
        $$ = default_expr_error_value();
        $$.type = "BOOL"; // Result is always BOOL
        $$.value = malloc(sizeof(bool));
        if ((strcmp($1.type, "INT") == 0 || strcmp($1.type, "REAL") == 0) &&
            (strcmp($3.type, "INT") == 0 || strcmp($3.type, "REAL") == 0)) {
            // Warning
            if (strcmp($1.type, "INT") == 0 && strcmp($3.type, "REAL") == 0) {
                yywarning("Implicit conversion from int to real in addition (left operand).");
            } else if (strcmp($1.type, "REAL") == 0 && strcmp($3.type, "INT") == 0) {
                yywarning("Implicit conversion from int to real in addition (right operand).");
            }
            float val1 = (strcmp($1.type, "INT") == 0) ? (float)(*(int*)$1.value) : (*(float*)$1.value);
            float val2 = (strcmp($3.type, "INT") == 0) ? (float)(*(int*)$3.value) : (*(float*)$3.value);
            *(bool *)$$.value = val1 != val2;
        } else if (strcmp($1.type, "STRING") == 0 && strcmp($3.type, "STRING") == 0) {
             *(bool *)$$.value = strcmp((char*)$1.value, (char*)$3.value) != 0;
        }
        else {
            yyerror("Type mismatch in not equal comparison");
            *(bool *)$$.value = false; // Default on error
        }
        if ($1.value) free($1.value);
        if ($3.value) free($3.value);
    }
    | OP_NOT expression {
        // Logical NOT
        $$ = default_expr_error_value();
        if (strcmp($2.type, "BOOL") == 0) {
            $$.type = "BOOL";
            $$.value = malloc(sizeof(bool));
            *(bool *)$$.value = !(*(bool *)$2.value);
        } else {
            yyerror("Invalid type for logical NOT");
        }
        if ($2.value) free($2.value); // Free operand value
    }
    | expression OP_AND expression {
        // Logical AND
        $$ = default_expr_error_value();
        if (strcmp($1.type, "BOOL") == 0 && strcmp($3.type, "BOOL") == 0) {
            $$.type = "BOOL";
            $$.value = malloc(sizeof(bool));
            *(bool *)$$.value = (*(bool *)$1.value) && (*(bool *)$3.value);
        } else {
            yyerror("Type mismatch in logical AND");
        }
        if ($1.value) free($1.value); // Free operand values
        if ($3.value) free($3.value);
    }
    | expression OP_OR expression {
        // Logical OR
        $$ = default_expr_error_value();
        if (strcmp($1.type, "BOOL") == 0 && strcmp($3.type, "BOOL") == 0) {
            $$.type = "BOOL";
            $$.value = malloc(sizeof(bool));
            *(bool *)$$.value = (*(bool *)$1.value) || (*(bool *)$3.value);
        } else {
            yyerror("Type mismatch in logical OR");
        }
        if ($1.value) free($1.value); // Free operand values
        if ($3.value) free($3.value);
    }
    | DELIM_LPAR expression DELIM_RPAR {
        // Parentheses
        $$.type = $2.type;
        $$.value = $2.value;
    }
    ;

expression:
    INT {
        $$.type = "INT";
        $$.value = malloc(sizeof(int));
        *(int *)$$.value = $1;
        // printf("Expression type: INT, value: %d\n", $1); // for debugging
    }
    | REAL {
        $$.type = "REAL";
        $$.value = malloc(sizeof(float));
        *(float *)$$.value = $1;
        // printf("Expression type: REAL, value: %f\n", $1); // for debugging
    }
    | BOOL {
        $$.type = "BOOL";
        $$.value = malloc(sizeof(bool));
        *(bool *)$$.value = $1;
        // printf("Expression type: BOOL, value: %s\n", $1 ? "true" : "false"); // for debugging
    }
    | STRING {
        $$.type = "STRING";
        $$.value = strdup($1);
        // printf("Expression type: STRING, value: %s\n", $1); // for debugging
    }
    | ID {
        Symbol *symbol = lookupSymbol(currentTable, $1);
        if (!symbol) {
            yyerror("Variable not declared");
            $$ = default_expr_error_value(); // Set to error value
        } else {
            if (strcmp(symbol->type, "int") == 0) {
                $$.type = "INT";
            } else if (strcmp(symbol->type, "float") == 0 || strcmp(symbol->type, "double") == 0) {
                $$.type = "REAL";
            } else if (strcmp(symbol->type, "bool") == 0) {
                $$.type = "BOOL";
            } else if (strcmp(symbol->type, "string") == 0 || strcmp(symbol->type, "char") == 0) {
            }
        }
    }
    | arithmetic_expression
    | function_invocation {
        // void function(procedure) has no return value
        if (strcmp($1.type, "void") == 0) {
            yyerror("Void function cannot be used in expression");
            if ($1.type) {
                free($1.type); // Free the value if it was allocated
            }
            $$ = default_expr_error_value(); // Set to error value
        } else {
            if (strcmp($1.type, "int") == 0) {
                $$.type = "INT";
                $$.value = NULL;
                // $$.value = malloc(sizeof(int));
                // *(int *)$$.value = *(int *)$1.value;
            } else if (strcmp($1.type, "float") == 0 || strcmp($1.type, "double") == 0) {
                $$.type = "REAL";
                $$.value = NULL;
                // $$.value = malloc(sizeof(float));
                // *(float *)$$.value = *(float *)$1.value;
            } else if (strcmp($1.type, "bool") == 0) {
                $$.type = "BOOL";
                $$.value = NULL;
                // $$.value = malloc(sizeof(bool));
                // *(bool *)$$.value = *(bool *)$1.value;
            } else if (strcmp($1.type, "string") == 0 || strcmp($1.type, "char") == 0) {
                $$.type = "STRING";
                $$.value = NULL;
                // $$.value = strdup((char *)$1.value);
            } else {
                yyerror("Invalid function return type");
                $$ = default_expr_error_value(); // Set to error value
            }
            if ($1.value) {
                free($1.value); // Free the value if it was allocated
            }
        }
    }
    ;

assignment:
    ID OP_ASSIGN expression DELIM_SEMICOLON {   
        Symbol *symbol = lookupSymbol(currentTable, $1);
        if (!symbol) {
            yyerror("Variable not declared");
        } else if (symbol->isConst) {
            yyerror("Cannot assign to a constant variable");
        } else {
            bool type_match_exact = false;
            bool type_compatible_with_warning = false;

            // check if the type of the variable matches the type of the expression
            if (strcmp(symbol->type, "int") == 0 && strcmp($3.type, "INT") == 0) {
                // // int to int assignment
                type_match_exact = true;
                // symbol->value.intValue = *(int *)$3.value;
            } else if ((strcmp(symbol->type, "float") == 0) || (strcmp(symbol->type, "double") == 0) && strcmp($3.type, "REAL") == 0) {
                // // float to float assignment
                type_match_exact = true;
                // symbol->value.realValue = *(float *)$3.value;
            } else if (strcmp(symbol->type, "bool") == 0 && strcmp($3.type, "BOOL") == 0) {
                // // bool to bool assignment
                type_match_exact = true;
                // symbol->value.boolValue = *(bool *)$3.value;
            } else if ((strcmp(symbol->type, "char") == 0) || (strcmp(symbol->type, "string") == 0) && strcmp($3.type, "STRING") == 0) {
                // // string to string assignment
                type_match_exact = true;
                // free(symbol->value.stringValue); // free old value
                // symbol->value.stringValue = strdup((char *)$3.value);
            } 
            else if ((strcmp(symbol->type, "float") == 0 || strcmp(symbol->type, "double") == 0) && strcmp($3.type, "INT") == 0) {
                // Assigning int to float/double
                type_compatible_with_warning = true;
                yywarning("Implicit conversion from int to float/double in assignment");
                // symbol->value.realValue = (float)(*(int *)$3.value);
            } else if (strcmp(symbol->type, "int") == 0 && strcmp($3.type, "REAL") == 0) {
                // Assigning float/double to int
                type_compatible_with_warning = true;
                yywarning("Implicit conversion from float/double to int in assignment (May cause data loss)");
                // symbol->value.realValue = *(float *)$3.value;
            }
            
            if (!type_match_exact && !type_compatible_with_warning) {
                yyerror("Type mismatch in assignment");
            } 
            
        if ($3.value)
            free($3.value); // release value of expression
        }
    }
    ;

statements:
    statement statements
    | /* empty */
    ;

statement:
    block
    | simple
    | conditional
    | loop
    | return_statement
    | declaration
    ;

block:
    DELIM_LBRACE {
        //create a new symbol table for block
        SymbolTable *newTable = createSymbolTable(currentTable);
        currentTable = newTable;
    }
    statements
    DELIM_RBRACE{
        // dump and delete the current symbol table, currnet table set to parent table
        SymbolTable *parentTable = currentTable->parent;
        dumpSymbolTable(currentTable);
        deleteSymbolTable(currentTable);
        currentTable = parentTable;
    }
    ;

simple:
    assignment
    | print
    | increment_decrement
    | semicolon_only
    | arithmetic_expression DELIM_SEMICOLON
    | function_invocation DELIM_SEMICOLON
    ;

print:
    KW_PRINT expression DELIM_SEMICOLON {
        // printf("Print statement: %s\n", $2); // for debugging
        if (strcmp($2.type, "INT") == 0) {
            // printf("%d", *(int *)$2.value);
        } else if (strcmp($2.type, "REAL") == 0) {
            // printf("%f", *(float *)$2.value);
        } else if (strcmp($2.type, "BOOL") == 0) {
            // printf("%s", *(bool *)$2.value ? "true" : "false");
        } else if (strcmp($2.type, "STRING") == 0) {
            // printf("%s", (char *)$2.value);
        } else {
            yyerror("Invalid type for print statement");
        }
    }
    | KW_PRINTLN expression DELIM_SEMICOLON {
        // printf("Println statement: %s\n", $2); // for debugging
        if (strcmp($2.type, "INT") == 0) {
            // printf("%d\n", *(int *)$2.value);
        } else if (strcmp($2.type, "REAL") == 0) {
            // printf("%f\n", *(float *)$2.value);
        } else if (strcmp($2.type, "BOOL") == 0) {
            // printf("%s\n", *(bool *)$2.value ? "true" : "false");
        } else if (strcmp($2.type, "STRING") == 0) {
            // printf("%s\n", (char *)$2.value);
        } else {
            yyerror("Invalid type for println statement");
        }
    }
    ;

increment_decrement:
    ID OP_INC DELIM_SEMICOLON {
        // printf("Increment statement: %s\n", $1); // for debugging
        Symbol *symbol = lookupSymbol(currentTable, $1);
        if (!symbol) {
            yyerror("Variable not declared");
        } else if (symbol->isConst) {
            yyerror("Cannot assign to a constant variable");
        } else {
            if (strcmp(symbol->type, "int") == 0) {
                // symbol->value.intValue++;
            } else if (strcmp(symbol->type, "float") == 0 || strcmp(symbol->type, "double") == 0) {
                // symbol->value.realValue++;
            } else {
                yyerror("Invalid type for increment statement");
            }
        }
    }
    | ID OP_DEC DELIM_SEMICOLON {
        // printf("Decrement statement: %s\n", $1); // for debugging
        Symbol *symbol = lookupSymbol(currentTable, $1);
        if (!symbol) {
            yyerror("Variable not declared");
        } else if (symbol->isConst) {
            yyerror("Cannot assign to a constant variable");
        } else {
            if (strcmp(symbol->type, "int") == 0) {
                // int decrement
            } else if (strcmp(symbol->type, "float") == 0 || strcmp(symbol->type, "double") == 0) {
                // real decrement
            } else {
                yyerror("Invalid type for decrement statement");
            }
        }
    }
    ;

semicolon_only:
    DELIM_SEMICOLON
    ;

conditional:
    KW_IF DELIM_LPAR expression DELIM_RPAR simple {
        // printf("If statement: %s\n", $3); // for debugging
        if (strcmp($3.type, "BOOL") == 0) {
            // if (*(bool *)$3.value) {
            //     // execute simple statement
            // } else {
            //     // skip simple statement
            // }
        } else {
            yyerror("Invalid type for if condition");
        }
    }
    | KW_IF DELIM_LPAR expression DELIM_RPAR block {
        // printf("If statement\n"); // for debugging
        if (strcmp($3.type, "BOOL") == 0) {
            // if (*(bool *)$3.value) {
            //     // execute block
            // } else {
            //     // skip block
            // }
        } else {
            yyerror("Invalid type for if condition");
        }
    }
    | KW_IF DELIM_LPAR expression DELIM_RPAR simple KW_ELSE simple {
        // printf("If-else statement\n"); // for debugging
        if (strcmp($3.type, "BOOL") == 0) {
            // if (*(bool *)$3.value) {
            //     // execute first block
            // } else {
            //     // execute second block
            // }
        } else {
            yyerror("Invalid type for if condition");
        }
    }
    | KW_IF DELIM_LPAR expression DELIM_RPAR simple KW_ELSE block {
        // printf("If-else statement\n"); // for debugging
        if (strcmp($3.type, "BOOL") == 0) {
            // if (*(bool *)$3.value) {
            //     // execute first block
            // } else {
            //     // execute second block
            // }
        } else {
            yyerror("Invalid type for if condition");
        }
    }
    | KW_IF DELIM_LPAR expression DELIM_RPAR block KW_ELSE simple {
        // printf("If-else statement\n"); // for debugging
        if (strcmp($3.type, "BOOL") == 0) {
            // if (*(bool *)$3.value) {
            //     // execute first block
            // } else {
            //     // execute second block
            // }
        } else {
            yyerror("Invalid type for if condition");
        }
    }
    | KW_IF DELIM_LPAR expression DELIM_RPAR block KW_ELSE block {
        // printf("If-else statement\n"); // for debugging
        if (strcmp($3.type, "BOOL") == 0) {
            // if (*(bool *)$3.value) {
            //     // execute first block
            // } else {
            //     // execute second block
            // }
        } else {
            yyerror("Invalid type for if condition");
        }
    }
    ;

loop:
    KW_WHILE DELIM_LPAR expression DELIM_RPAR simple {
        // printf("While statement: %s\n", $3); // for debugging
        if (strcmp($3.type, "BOOL") == 0) {
            // while (*(bool *)$3.value) {
            //     // execute simple statement
            // }
        } else {
            yyerror("Invalid type for while condition");
        }
    }
    | KW_WHILE DELIM_LPAR expression DELIM_RPAR block {
        // printf("While statement\n"); // for debugging
        if (strcmp($3.type, "BOOL") == 0) {
            // while (*(bool *)$3.value) {
            //     // execute block
            // }
        } else {
            yyerror("Invalid type for while condition");
        }
    }
    | KW_FOR DELIM_LPAR simple DELIM_SEMICOLON expression DELIM_SEMICOLON simple DELIM_RPAR simple {
        // printf("For statement\n"); // for debugging
        if (strcmp($5.type, "BOOL") == 0) {
            // while (*(bool *)$5.value) {
            //     // execute simple statement
            // }
        } else {
            yyerror("Invalid type for for condition");
        }
    }
    | KW_FOR DELIM_LPAR simple DELIM_SEMICOLON expression DELIM_SEMICOLON simple DELIM_RPAR block {
        // printf("For statement\n"); // for debugging
        if (strcmp($5.type, "BOOL") == 0) {
            // while (*(bool *)$5.value) {
            //     // execute simple statement
            // }
        } else {
            yyerror("Invalid type for for condition");
        }
    }
    | KW_FOREACH DELIM_LPAR ID DELIM_COLON expression DELIM_DOT DELIM_DOT expression DELIM_RPAR simple {
        if (strcmp($5.type, "INT") != 0 || strcmp($8.type, "INT") != 0) {
            yyerror("Foreach range must be integers");
        } else {
            // int start = *(int *)$5.value;
            // int end = *(int *)$7.value;

            // for (int i = start; i <= end; i++) {
            //     // execute simple statement
            //     Symbol *symbol = lookupSymbol(currentTable, $3);
            //     if (!symbol) {
            //         yyerror("Variable not declared");
            //     } else if (symbol->isConst) {
            //         yyerror("Cannot assign to a constant variable");
            //     } else {
            //         symbol->value.intValue = i;
            //     }
            //     // execute simple statement
            // }
        }
    }
    | KW_FOREACH DELIM_LPAR ID DELIM_COLON expression DELIM_DOT DELIM_DOT expression DELIM_RPAR block {
        if (strcmp($5.type, "INT") != 0 || strcmp($8.type, "INT") != 0) {
            yyerror("Foreach range must be integers");
        } else {
            // int start = *(int *)$5.value;
            // int end = *(int *)$7.value;

            // for (int i = start; i <= end; i++) {
            //     // execute simple statement
            //     Symbol *symbol = lookupSymbol(currentTable, $3);
            //     if (!symbol) {
            //         yyerror("Variable not declared");
            //     } else if (symbol->isConst) {
            //         yyerror("Cannot assign to a constant variable");
            //     } else {
            //         symbol->value.intValue = i;
            //     }
            //     // execute block
            // }
        }
    }
    ;

return_statement:
    KW_RETURN expression DELIM_SEMICOLON {
        if (current_function_return_type_for_return_check != NULL) { // inside a function
            if (strcmp(current_function_return_type_for_return_check, "void") == 0) {
                yyerror("Void function cannot return a value");
            } else { // non-void function
                bool type_match = false;
                char *func_return_type_str = current_function_return_type_for_return_check;
                char *expr_type_str = $2.type;

                // compare funciton's declared return type with the expression's type
                if (strcmp(func_return_type_str, "int") == 0 && strcmp(expr_type_str, "INT") == 0) {
                    type_match = true;
                } else if ((strcmp(func_return_type_str, "float") == 0 || strcmp(func_return_type_str, "double") == 0) && strcmp(expr_type_str, "REAL") == 0) {
                    type_match = true;
                } else if (strcmp(func_return_type_str, "bool") == 0 && strcmp(expr_type_str, "BOOL") == 0) {
                    type_match = true;
                } else if ((strcmp(func_return_type_str, "char") == 0 || strcmp(func_return_type_str, "string") == 0) && strcmp(expr_type_str, "STRING") == 0) {
                    type_match = true;
                }

                if (!type_match) {
                    yyerror("Return type mismatch in function");
                } else {
                    non_void_function_has_return_value_statement = true; // set flag to true
                }
            }
        } else {
            yyerror("Return statement outside of a function.");
        }
    }
    | KW_RETURN DELIM_SEMICOLON { // return; (without an expression)
        if (current_function_return_type_for_return_check != NULL) { // Inside a function
            if (strcmp(current_function_return_type_for_return_check, "void") == 0) {
                // void function must not have a return statement"
                yyerror("Void function cannot have any return statement");
            } else { // Non-void function
                yyerror("Non-void function must return a value");
            }
        } else {
            yyerror("Return statement outside of a function.");
        }
    }
    ;

function_declaration:
    type_specifier ID DELIM_LPAR parameter_list DELIM_RPAR DELIM_LBRACE {
        // check if the function is already declared
        if (lookupFunction(functionTable, $2)) {
            yyerror("Function already declared");
        } else {
            // check if parameter list has duplicate names
            Parameter *param = $4;
            while (param != NULL) {
                Parameter *nextParam = param->next;
                while (nextParam != NULL) {
                    if (strcmp(param->name, nextParam->name) == 0) {
                        yyerror("Duplicate parameter name in function declaration");
                    }
                    nextParam = nextParam->next;
                }
                param = param->next;
                if (param != NULL) // Avoid dereferencing NULL pointer
                    nextParam = param->next;
            }
            // add function to the function table
            insertFunction(functionTable, $2, $1, $4);

            current_function_name_for_return_check = $2;
            current_function_return_type_for_return_check = $1; // store the declared return type
            non_void_function_has_return_value_statement = false; // reset for this function
        }
        //create a new symbol table for block
        SymbolTable *newTable = createSymbolTable(currentTable);
        currentTable = newTable;
        // add all arguments to the symbol table
        Parameter *param = $4;
        while (param != NULL) {
            insertSymbol(currentTable, param->name, param->type, 0);
            param = param->next;
        }
    }
    statements
    DELIM_RBRACE {
        // check if funciton has return statement
        if (strcmp(current_function_return_type_for_return_check, "void") != 0) {
            if (!non_void_function_has_return_value_statement) {
                yyerror("Non-void function must have a return statement");
            }
        }
        // dump and delete the current symbol table, currnet table set to parent table
        SymbolTable *parentTable = currentTable->parent;
        dumpSymbolTable(currentTable);
        deleteSymbolTable(currentTable);
        currentTable = parentTable;

        // clear function helpsers
        current_function_name_for_return_check = NULL;
        current_function_return_type_for_return_check = NULL;
    }
    | KW_VOID ID DELIM_LPAR parameter_list DELIM_RPAR DELIM_LBRACE {
        // check if the function is already declared
        if (lookupFunction(functionTable, $2)) {
            yyerror("Function already declared");
        } else {
            // check if parameter list has duplicate names
            Parameter *param = $4;
            while (param != NULL) {
                Parameter *nextParam = param->next;
                while (nextParam != NULL) {
                    if (strcmp(param->name, nextParam->name) == 0) {
                        yyerror("Duplicate parameter name in function declaration");
                    }
                    nextParam = nextParam->next;
                }
                param = param->next;
                if (param != NULL) // Avoid dereferencing NULL pointer
                    nextParam = param->next;
            }
            // add function to the function table
            insertFunction(functionTable, $2, "void", $4);

            current_function_name_for_return_check = $2;
            current_function_return_type_for_return_check = "void"; // store the declared return type
            non_void_function_has_return_value_statement = false; // reset for this function
        }
        //create a new symbol table for block
        SymbolTable *newTable = createSymbolTable(currentTable);
        currentTable = newTable;
        // add all arguments to the symbol table
        Parameter *param = $4;
        while (param != NULL) {
            insertSymbol(currentTable, param->name, param->type, 0);
            param = param->next;
        }
    }
    statements
    DELIM_RBRACE {
        // for void function, check it has no return statement
        // will be handled in "return_statement" rule

        // dump and delete the current symbol table, currnet table set to parent table
        SymbolTable *parentTable = currentTable->parent;
        dumpSymbolTable(currentTable);
        deleteSymbolTable(currentTable);
        currentTable = parentTable;

        current_function_name_for_return_check = NULL;
        current_function_return_type_for_return_check = NULL;
    }
    ;

parameter_list: 
    type_specifier ID {
        // single parameter
        $$ = (Parameter *)malloc(sizeof(Parameter));
        $$->name = strdup($2);
        $$->type = strdup($1);
        $$->next = NULL;
    }
    | type_specifier ID DELIM_COMMA parameter_list {
        // multiple parameters
        $$ = (Parameter *)malloc(sizeof(Parameter));
        $$->name = strdup($2);
        $$->type = strdup($1);
        $$->next = $4;
    }
    | /* empty */ {
        // no parameters
        $$ = NULL;
    }
    ;

function_invocation:
    ID DELIM_LPAR argument_list DELIM_RPAR {
        // check if the function is declared
        $$ = default_expr_error_value();
        Function *func = lookupFunction(functionTable, $1);
        if (!func) {
            yyerror("Function not declared");
        } else {
            // check if the number of arguments matches the number of parameters
            int numArgs = 0;
            Parameter *arg = $3;
            while (arg != NULL) {
                numArgs++;
                arg = arg->next;
            }
            int numParams = 0;
            Parameter *param = func->parameters;
            while (param != NULL) {
                numParams++;
                param = param->next;
            }
            if (numArgs != numParams) {
                yyerror("Number of arguments does not match number of parameters");
            } else {
                // check if the types of arguments match the types of parameters
                arg = $3;
                param = func->parameters;
                bool type_mismatch = false;
                int arg_count = 0;
                while (arg != NULL && param != NULL) {
                    arg_count++;
                    bool current_arg_type_match = false;
                    if (strcmp(arg->type, "INT") == 0 && strcmp(param->type, "int") == 0) {
                        current_arg_type_match = true;
                    } else if (strcmp(arg->type, "REAL") == 0 && (strcmp(param->type, "string") == 0 || strcmp(param->type, "double") == 0)) {
                        current_arg_type_match = true;
                    } else if (strcmp(arg->type, "BOOL") == 0 && strcmp(param->type, "bool") == 0) {
                        current_arg_type_match = true;
                    } else if (strcmp(arg->type, "STRING") == 0 && (strcmp(param->type, "string") == 0 || strcmp(param->type, "char") == 0)) {
                        current_arg_type_match = true;
                    }
                    if (!current_arg_type_match) {
                        type_mismatch = true;
                        yyerror("Type mismatch in function invocation");
                        break; // exit the loop on type mismatch
                    }
                    arg = arg->next;
                    param = param->next;
                }
                if (!type_mismatch) {
                    // function invocation is valid
                    $$.type = strdup(func->type);
                    if (strcmp(func->type, "void") == 0) {
                        $$.value = NULL; // void function has no return value
                    } else {
                        $$.value = NULL; // no need to store value
                    }
                }
            }
            Parameter *temp_arg = $3;
            while (temp_arg != NULL) {
                Parameter *next_arg = temp_arg->next;
                if (temp_arg->type)
                    free(temp_arg->type);
                // if (temp_arg->value) free(temp_arg->value);
                free(temp_arg);
                temp_arg = next_arg;
            }
        }
    }
    ;

argument_list_actual:
    expression {
        // single argument
        $$ = (Parameter *)malloc(sizeof(Parameter));
        if (!$$) {
            yyerror("Memory allocation failed for argument list");
            exit(1);
        }
        $$->name = NULL; // no name for actual argument
        $$->type = strdup($1.type);
        $$->next = NULL;


    }
    | expression DELIM_COMMA argument_list_actual {
        // multiple arguments
        $$ = (Parameter *)malloc(sizeof(Parameter));
        if (!$$) {
            yyerror("Memory allocation failed for argument list");
            exit(1);
        }
        $$->name = NULL; // no name for actual argument
        $$->type = strdup($1.type);
        $$->next = $3;
    }
    ;

argument_list:
    argument_list_actual {
        $$ = $1;
    }
    | /* empty */ {
        $$ = NULL;
    }
    ;
    
%%

int main(int argc, char **argv) {
    if (argc != 2) {
        printf("Usage: %s <input file>\n", argv[0]);
        return 1;
    }

    yyin = fopen(argv[1], "r");
    if (!yyin) {
        perror("fopen");
        return 1;
    }

    // get file name
    std::string filename(argv[1]);
    size_t last_dot = filename.find_last_of('.');
    std::string class_name = (last_dot == std::string::npos) ? filename : filename.substr(0, last_dot);

    // create class code generator
    CodeGenerator codeGen(class_name);

    printf("Starting parsing...\n");

    // Initialize the symbol table
    currentTable = createSymbolTable(NULL);
    functionTable = createFunctionTable();

    // int token;
    // while ((token = yylex()) != 0) {
    //     printf("Line%d, Token: %s, Text: %s\n", linenum, token_names[token - 258], yytext);
    // }

    if (yyparse() == 0) {
        // Dump and delete globol symbol table
        dumpSymbolTable(currentTable);
        deleteSymbolTable(currentTable);
        currentTable = NULL;
        deleteFunctionTable(functionTable);
        functionTable = NULL;
        printf("Parsing done.\n");
    } else {
        printf("Parsing failed.\n");
    }

    fclose(yyin);
    return 0;
    
}