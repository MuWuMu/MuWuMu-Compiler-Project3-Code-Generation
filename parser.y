%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>

#include "symbol_table.h"
#include "function_table.h"
#include "expr_value.h"
// #include "array_utils.h"

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
    DimensionInfo *dim_info; // For array dimensions
    IndexAccessInfo *idx_acc_info; // For array access indices
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
%type <node> array_initializer
%type <param> parameter_list
%type <param> argument_list
%type <param> argument_list_actual
%type <expr_val> function_invocation
%type <dim_info> dimension_specifiers
%type <idx_acc_info> array_indices

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
                switch (current->type) {
                    case "INT":
                        if ($1 != "int")
                            yyerror("Type mismatch in declaration");
                    case "REAL":
                        if ($1 != "float" && $1 != "double")
                            yyerror("Type mismatch in declaration");
                    case "BOOL":
                        if ($1 != "bool")
                            yyerror("Type mismatch in declaration");
                    case "STRING":
                        if ($1 != "string" && $1 != "char")
                            yyerror("Type mismatch in declaration");
                }
            } else {
                insertSymbol(currentTable, current->name, $1, 0, 0, NULL, NULL/*current->value*/);
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
                switch (current->type) {
                    case "INT":
                        if ($2 != "int")
                            yyerror("Type mismatch in declaration");
                    case "REAL":
                        if ($2 != "float" && $2 != "double")
                            yyerror("Type mismatch in declaration");
                    case "BOOL":
                        if ($2 != "bool")
                            yyerror("Type mismatch in declaration");
                    case "STRING":
                        if ($2 != "string" && $2 != "char")
                            yyerror("Type mismatch in declaration");
                }
            } else if (current->value == NULL) {
                yyerror("Const variable must be initialized");
            } else {
                insertSymbol(currentTable, current->name, $2, 1, 0, NULL, NULL/*current->value*/); // set as const
                // printf("Initialized const variable: %s with value\n", current->name);   // for debugging
            }
            current = current->next;
        }
    }
    // array declaration
    | array_declaration
    ;

dimension_specifiers:
    DELIM_LBRACK INT DELIM_RBRACK {
        if ($2 <= 0) {
            yyerror("Array size must be greater than 0");
        } 
        $$ = create_dimension_list($2);
    }
    | dimension_specifiers DELIM_LBRACK INT DELIM_RBRACK {
        if ($3 <= 0) {
            yyerror("Array size must be greater than 0");
        } 
        $$ = add_dimension_to_list($1, $3);
    }

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
        $$->type = $3.type;
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

array_declaration:
    type_specifier ID dimension_specifiers DELIM_SEMICOLON {
        printf("Array declaration without initialization: type=%s\n", $1);    // for debugging
        if (lookupSymbolInCurrentTable(currentTable, $2)) {
            yyerror("Duplicate declaration of array");
            free_dimension_info($3); // free dimension info
        } else {
            insertSymbol(currentTable, $2, $1, 0, 1, $3, NULL); // NULL for no initialization
            // void *arr_data = create_md_array_data($1, $3); // $1 is string, $3 is DimensionInfo
            // if (arr_data) {
            //     initialize_md_array_data(arr_data, $1, $3, NULL); // NULL to default init
            //     insertSymbol(currentTable, $2, $1, 0, 1, $3, arr_data);
            // } else {
            //     yyerror("Failed to create multi-dimensional array data");
            //     free_dimension_info($3); // free dimension info
            // }
            if ($3) {
                free_dimension_info($3); // free dimension info
            }
        }
    }
    | type_specifier ID dimension_specifiers OP_ASSIGN DELIM_LBRACE array_initializer DELIM_RBRACE DELIM_SEMICOLON {
        printf("Array declaration with initialization: type=%s\n", $1);    // for debugging
        if (lookupSymbolInCurrentTable(currentTable, $2)) {
            yyerror("Duplicate declaration of array");
        } else {
            insertSymbol(currentTable, $2, $1, 0, 1, $3, NULL); // NULL for no initialization
            // long total_elements = $3->total_elements; // total number of elements in the array
            // int num_inits = count_initializers($6); // Node*
            // if (num_inits > total_elements) {
            //     yyerror("Too many initializers for array");
            //     free_dimension_info($3); // free dimension info
            // } else {
            //     void *arr_data = create_md_array_data($1, $3);
            //     if (arr_data) {
            //         initialize_md_array_data(arr_data, $1, $3, $6);
            //         insertSymbol(currentTable, $2, $1, 0, 1, $3, arr_data);
            //     } else {
            //         yyerror("Failed to create multi-dimensional array data");
            //         free_dimension_info($3); // free dimension info
            //     }
            //     // last, free array_initializer list
            //     Node *curr = $6, *next_node;
            //     while (curr) {
            //         next_node = curr->next;
            //         if (curr->value) {
            //             free(curr->value);
            //         }
            //         free(curr);
            //         curr = next_node;
            //     }
            // }
        }
        if ($3) {
            free_dimension_info($3); // free dimension info
        }

        // clean array_initializer list
        Node *curr = $6, *next_node;
        while (curr != NULL) {
            next_node = curr->next;
            if (curr->value) {
                free(curr->value);
            }
            free(curr);
            curr = next_node;
        }
    }
    | KW_CONST type_specifier ID dimension_specifiers OP_ASSIGN DELIM_LBRACE array_initializer DELIM_RBRACE DELIM_SEMICOLON {
        printf("Const array declaration with initialization: type=%s\n", $2);    // for debugging
        if (lookupSymbolInCurrentTable(currentTable, $3)) {
            yyerror("Duplicate declaration of array");
        } else {
            insertSymbol(currentTable, $3, $2, 1, 1, $4, NULL); // NULL for no initialization
            // long total_elements = $4->total_elements;
            // int num_inits = count_initializers($7);
            // if (num_inits > total_elements) {
            //     yyerror("Too many initializers for const array");
            //     free_dimension_info($4); // free dimension info
            // } else {
            //     void *arr_data = create_md_array_data($2, $4);
            //     if (arr_data) {
            //         initialize_md_array_data(arr_data, $2, $4, $7);
            //         insertSymbol(currentTable, $3, $2, 1, 1, $4, arr_data); // set as const
            //     } else {
            //         yyerror("Failed to create multi-dimensional const array data");
            //         free_dimension_info($4); // free dimension info
            //     }
            //     // free array_initializer list
            //     Node *curr = $7, *next_node;
            //     while (curr) {
            //         next_node = curr->next;
            //         if (curr->value) {
            //             free(curr->value);
            //         }
            //         free(curr);
            //         curr = next_node;
            //     }
            // }
        }
        if ($4) {
            free_dimension_info($4); // free dimension info
        }

        // clean array_initializer list
        Node *curr = $7, *next_node;
        while (curr != NULL) {
            next_node = curr->next;
            if (curr->value) {
                free(curr->value);
            }
            free(curr);
            curr = next_node;
        }
    }
    | KW_CONST type_specifier ID dimension_specifiers DELIM_SEMICOLON {
        // const array declaration without initialization (invalid)
        yyerror("Const array must be initialized");
        if ($4) {
            free_dimension_info($4); // free dimension info
        }
    }
    ;

array_initializer:
    expression {
        // single initialization value
        $$ = (Node *)malloc(sizeof(Node));
        $$->value = $1.value;
        $$->next = NULL;
    }
    | expression DELIM_COMMA array_initializer {
        // multi initialization values
        $$ = (Node *)malloc(sizeof(Node));
        $$->value = $1.value;
        $$->next = $3;
    }
    ;

array_indices:
    DELIM_LBRACK expression DELIM_RBRACK {
        if (strcmp($2.type, "INT") != 0) {
            yyerror("Array index must be an integer");
            if ($2.value) {
                free($2.value); // free the value if it was allocated
            }
            $$ = NULL; // set to NULL to avoid using uninitialized value
        } else {
            $$ = (IndexAccessInfo *)malloc(sizeof(IndexAccessInfo));
            if (!$$) {
                yyerror("Memory allocation failed for array index access info");
                if ($2.value) {
                    free($2.value); // free the value if it was allocated
                }
            }
            $$->num_indices = 1; // single index
            $$->indices = (int *)malloc(sizeof(int));
            if (!$$->indices) {
                yyerror("Memory allocation failed for indices array");
                free($$); // free the IndexAccessInfo struct
                if ($2.value) {
                    free($2.value); // free the value if it was allocated
                }
            }
            $$->indices[0] = *(int *)$2.value; // store the index value
            free($2.value); // free the value after using it
        }
    }
    | array_indices DELIM_LBRACK expression DELIM_RBRACK {
        if (!$1) { // Error in preceding part of index list
            if ($3.value) free($3.value);
            $$ = NULL;
            YYERROR; // Propagate error
        } else if (strcmp($3.type, "INT") != 0) {
            yyerror("Array index must be an integer expression");
            if ($3.value) free($3.value);
            // Clean up $1
            free($1->indices);
            free($1);
            $$ = NULL;
            YYERROR;
        } else {
            int new_num_indices = $1->num_indices + 1;
            int *new_indices_ptr = (int *)realloc($1->indices, new_num_indices * sizeof(int));
            if (!new_indices_ptr) {
                yyerror("Memory reallocation failed for indices array");
                if ($3.value) free($3.value);
                free($1->indices); // Free old indices
                free($1);          // Free the IndexAccessInfo struct
                $$ = NULL;
                YYABORT; // Critical error
            }
            $1->indices = new_indices_ptr;
            $1->num_indices = new_num_indices;
            $1->indices[$1->num_indices - 1] = *(int *)$3.value;
            $$ = $1; // Pass along the extended list
            free($3.value); // Value consumed
        }
    }
    ;

arithmetic_expression:
    ID array_indices {
        Symbol *symbol = lookupSymbol(currentTable, $1);
        if (strcmp(symbol->type, "int") == 0) {
            $$.type = "INT";
        } else if (strcmp(symbol->type, "float") == 0 || strcmp(symbol->type, "double") == 0) {
            $$.type = "REAL";
        } else if (strcmp(symbol->type, "bool") == 0) {
            $$.type = "BOOL";
        } else if (strcmp(symbol->type, "char") == 0 || strcmp(symbol->type, "string") == 0) {
            $$.type = "STRING";
        } else {
            yyerror("Invalid type for array access");
        }
        $$.value = NULL;
        // array access
        // $$ = default_expr_error_value();
        // if (!$2) {
        //     yyerror("Invalid array access indices");
        // } else {
        //     Symbol *symbol = lookupSymbol(currentTable, $1);
        //     if (symbol == NULL) {
        //         yyerror("Undefined array variable");
        //     } else if (!symbol->isArray) {
        //         yyerror("Variable is not an array");
        //     } else if (symbol->dimensions->num_dimensions != $2->num_indices) {
        //         yyerror("Incorrect number of dimensions for array");
        //     } else {
        //         // bounds check
        //         bool bounds_ok = true;
        //         for (int i = 0; i < $2->num_indices; ++i) {
        //             if ($2->indices[i] < 0 || $2->indices[i] >= symbol->dimensions->sizes[i]) {
        //                 yyerror("Array index out of bounds");
        //                 bounds_ok = false;
        //                 break;
        //             }
        //         }

        //         if (bounds_ok) {
        //             void *element_ptr = get_md_array_element_ptr(symbol, $2);
        //             if (element_ptr) {
        //                 if (strcmp(symbol->type, "int") == 0) {
        //                     $$.type = "INT";
        //                     $$.value = NULL;
        //                     // $$.value = malloc(sizeof(int));
        //                     // *(int *)$$.value = *(int *)element_ptr;
        //                 } else if (strcmp(symbol->type, "float") == 0 || strcmp(symbol->type, "double") == 0) {
        //                     $$.type = "REAL";
        //                     $$.value = NULL;
        //                     // $$.value = malloc(sizeof(float));
        //                     // *(float *)$$.value = *(float *)element_ptr;
        //                 } else if (strcmp(symbol->type, "bool") == 0) {
        //                     $$.type = "BOOL";
        //                     $$.value = NULL;
        //                     // $$.value = malloc(sizeof(bool));
        //                     // *(bool *)$$.value = *(bool *)element_ptr;
        //                 } else if (strcmp(symbol->type, "char") == 0 || strcmp(symbol->type, "string") == 0) {
        //                     $$.type = "STRING";
        //                     $$.value = NULL;
        //                     // $$.value = strdup(*(char **)element_ptr);
        //                 } else {
        //                     yyerror("Unsupported array type");
        //                 }
        //             } else {
        //                 yyerror("Failed to access array element");
        //             }
        //         }
        //     }
        //     // clean up IndexAccessInfo
        //     if ($2) {
        //         free($2->indices);
        //         free($2);
        //     }
        // }
    }
    | OP_SUB expression %prec OP_INC {
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
        } else if (symbol->isArray) {
            yyerror("Need specify index for array variable");
            $$ = default_expr_error_value(); // Set to error value
        } else {
            if (strcmp(symbol->type, "int") == 0) {
                $$.type = "INT";
                $$.value = malloc(sizeof(int));
                *(int *)$$.value = symbol->value.intValue;
            } else if (strcmp(symbol->type, "float") == 0 || strcmp(symbol->type, "double") == 0) {
                $$.type = "REAL";
                $$.value = malloc(sizeof(float));
                *(float *)$$.value = symbol->value.realValue;
            } else if (strcmp(symbol->type, "bool") == 0) {
                $$.type = "BOOL";
                $$.value = malloc(sizeof(bool));
                *(bool *)$$.value = symbol->value.boolValue;
            } else if (strcmp(symbol->type, "string") == 0 || strcmp(symbol->type, "char") == 0) {
                $$.type = "STRING";
                $$.value = strdup(symbol->value.stringValue);
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
    | read
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

read:
    KW_READ ID DELIM_SEMICOLON {
        // printf("Read statement: %s\n", $2); // for debugging
        Symbol *symbol = lookupSymbol(currentTable, $2);
        if (!symbol) {
            yyerror("Variable not declared");
        } else if (symbol->isConst) {
            yyerror("Cannot assign to a constant variable");
        } else {
            if (strcmp(symbol->type, "int") == 0) {
                // int value;
                // scanf("%d", &value);
                // symbol->value.intValue = value;
            } else if (strcmp(symbol->type, "float") == 0 || strcmp(symbol->type, "double") == 0) {
                // float value;
                // scanf("%f", &value);
                // symbol->value.realValue = value;
            } else if (strcmp(symbol->type, "bool") == 0) {
                // bool value;
                // scanf("%d", &value);
                // symbol->value.boolValue = value;
            } else if (strcmp(symbol->type, "char") == 0 || strcmp(symbol->type, "string") == 0) {
                // char value[100];
                // scanf("%s", value);
                // free(symbol->value.stringValue); // free old value
                // symbol->value.stringValue = strdup(value);
            } else {
                yyerror("Invalid type for read statement");
            }
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
                symbol->value.intValue--;
            } else if (strcmp(symbol->type, "float") == 0 || strcmp(symbol->type, "double") == 0) {
                symbol->value.realValue--;
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
            insertSymbol(currentTable, param->name, param->type, 0, 0, NULL, NULL);
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
            insertSymbol(currentTable, param->name, param->type, 0, 0, NULL, NULL);
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
    /* 連夜趕工才發現自己根本越寫越歪，只要做syntax analysis就好，多做了很多沒用的功能，到最後程式變成一團spaghetti, bruh */
}