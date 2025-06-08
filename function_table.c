#include "function_table.h"

// Hash function
unsigned int hashForFunctions(const char *key) {
    unsigned int hash = 0;
    while (*key) {
        hash = (hash << 5) + *key++;
    }
    return hash % HASH_SIZE;
}

FunctionTable* createFunctionTable() {
    FunctionTable *table = (FunctionTable *)malloc(sizeof(FunctionTable));
    for (int i = 0; i < HASH_SIZE; i++) {
        table->table[i] = NULL;
    }
    return table;
}

void insertFunction(FunctionTable *table, const char *name, const char *type, Parameter *parameters) {
    unsigned int index = hashForFunctions(name);
    Function *function = (Function *)malloc(sizeof(Function));
    function->name = strdup(name);
    function->type = strdup(type);
    function->parameters = parameters;

    function->next = table->table[index]; // insert at the beginning of the linked list
    table->table[index] = function;
}

Function* lookupFunction(FunctionTable *table, const char *name) {
    unsigned int index = hashForFunctions(name);
    Function *function = table->table[index];
    while (function != NULL) {
        if (strcmp(function->name, name) == 0) {
            return function; // find
        }
        function = function->next;
    }
    return NULL; // not found
}

void deleteFunctionTable(FunctionTable *table) {
    for (int i = 0; i < HASH_SIZE; i++) {
        Function *function = table->table[i];
        while (function != NULL) {
            Function *temp = function;
            function = function->next;
            free(temp->name);
            free(temp->type);
            free(temp);
        }
    }
    free(table);
}