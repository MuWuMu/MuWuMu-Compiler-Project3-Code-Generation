#include "symbol_table.h"

// Hash function
unsigned int hash(const char *key) {
    unsigned int hash = 0;
    while (*key) {
        hash = (hash << 5) + *key++;
    }
    return hash % HASH_SIZE;
}

// New symbol table
SymbolTable* createSymbolTable(SymbolTable *parent) {
    SymbolTable *table = (SymbolTable *)malloc(sizeof(SymbolTable));
    for (int i = 0; i < HASH_SIZE; i++) {
        table->table[i] = NULL;
    }
    table->parent = parent;
    // printf("Create new symbol table\n"); // for debugging
    return table;
}

// Insert a symbol into a symbol table
void insertSymbol(SymbolTable *table, const char *name, const char *type, int isConst) {
    unsigned int index = hash(name);
    Symbol *symbol = (Symbol *)malloc(sizeof(Symbol));
    symbol->name = strdup(name);
    symbol->type = strdup(type);
    symbol->isConst = isConst;
    // Insert into hash table
    symbol->next = table->table[index];
    table->table[index] = symbol;
}

// Lookup a symbol in the symbol table
Symbol* lookupSymbol(SymbolTable *table, const char *name) {
    unsigned int index = hash(name);
    SymbolTable *current = table;
    while (current != NULL) {
        Symbol *symbol = current->table[index];
        while (symbol != NULL) {
            if (strcmp(symbol->name, name) == 0) {
                return symbol; // find
            }
            symbol = symbol->next;
        }
        current = current->parent; // keep search in parent table
    }
    return NULL; // not found
}

Symbol* lookupSymbolInCurrentTable(SymbolTable *table, const char *name) {
    unsigned int index = hash(name);
    Symbol *symbol = table->table[index];
    while (symbol != NULL) {
        if (strcmp(symbol->name, name) == 0) {
            return symbol; // find
        }
        symbol = symbol->next;
    }
    return NULL; // not found
}

// Delete symbol table
void deleteSymbolTable(SymbolTable *table) {
    if (table == NULL) return;
    for (int i = 0; i < HASH_SIZE; i++) {
        Symbol *symbol = table->table[i];
        while (symbol != NULL) {
            Symbol *temp = symbol;
            symbol = symbol->next;
            free(temp->name);
            free(temp->type);
            free(temp);
        }
    }
    free(table);
}

// Dump symbol table
void dumpSymbolTable(SymbolTable *table) {
    if (table == NULL) return;
    printf("Symbol Table:\n");

    for (int i = 0; i < HASH_SIZE; i++) {
        Symbol *symbol = table->table[i];
        if (symbol) {
            while (symbol != NULL) {
                printf(" Name: %s, Type: %s", symbol->name, symbol->type);
                if (symbol->isConst) {
                    printf("(const)");
                }
                printf("\n");
                symbol = symbol->next;
            }
        }
    }
}