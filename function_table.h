#ifndef FUNCTION_TABLE_H
#define FUNCTION_TABLE_H

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>

#define HASH_SIZE 211

typedef struct Parameter {
    char *name;
    char *type;
    struct Parameter *next;
} Parameter;

typedef struct Function {
    char *name;
    char *type;
    Parameter *parameters; // linked list of parameters

    struct Function *next; // for collision resolution
} Function;

typedef struct FunctionTable {
    Function *table[HASH_SIZE];
} FunctionTable;


FunctionTable* createFunctionTable();
void insertFunction(FunctionTable *table, const char *name, const char *type, Parameter *parameters);
Function* lookupFunction(FunctionTable *table, const char *name);
void deleteFunctionTable(FunctionTable *table);

unsigned int hashForFunctions(const char *key);

#endif