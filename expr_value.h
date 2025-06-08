#ifndef EXPR_VALUE_H
#define EXPR_VALUE_H

// Define a named struct for expression results
typedef struct ExprValue {
    char *type;
    void *value;
} ExprValue;

#endif