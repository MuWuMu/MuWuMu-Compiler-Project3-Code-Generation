#ifndef SYMBOL_TABLE_H
#define SYMBOL_TABLE_H

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>

#include "array_utils.h" // for DimensionInfo and array functions

#define HASH_SIZE 211

typedef struct Node {
    char *name;               // variable name
    char *type;               // variable type
    struct Node *next;       // pointer to next
    void *value;             // initial value if any
} Node;

// Symbol structure
typedef struct Symbol {
    char *name;       // id name
    char *type;       // id type
    int isConst;      // const or not
    int isArray;     // array or not
    // int arraySize;    // size of array if isArray is true
    struct DimensionInfo *dimensions; // for multi-dimensional array
    union {
        bool boolValue;
        int intValue;
        float realValue; 
        char *stringValue;
        // void *arrayValue;
    } value;             // value of the symbol
    struct Symbol *next; 
} Symbol;

// Symbol table structure
typedef struct SymbolTable {
    Symbol *table[HASH_SIZE];      // hash table
    struct SymbolTable *parent;    // point to parent table
} SymbolTable;

SymbolTable* createSymbolTable(SymbolTable *parent);
void insertSymbol(SymbolTable *table, const char *name, const char *type, int isConst, int isArray, struct DimensionInfo *dims, void *data_ptr_or_value_ptr);
Symbol* lookupSymbol(SymbolTable *table, const char *name);
Symbol* lookupSymbolInCurrentTable(SymbolTable *table, const char *name);
void deleteSymbolTable(SymbolTable *table);
void dumpSymbolTable(SymbolTable *table);

unsigned int hash(const char *key);

#endif