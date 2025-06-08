#include "array_utils.h"
#include "symbol_table.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

DimensionInfo* create_dimension_list(int first_dim_size) {
    DimensionInfo *dims = (DimensionInfo*)malloc(sizeof(DimensionInfo));
    if (!dims) {
        perror("Cannot allocate memory for dimension info");
        exit(EXIT_FAILURE);
    }
    dims->num_dimensions = 1;
    dims->sizes = (int*)malloc(sizeof(int));
    if (!dims->sizes) {
        perror("Cannot allocate memory for dimension sizes");
        free(dims);
        exit(EXIT_FAILURE);
    }
    dims->sizes[0] = first_dim_size;
    dims->total_elements = first_dim_size;
    return dims;
}

DimensionInfo* add_dimension_to_list(DimensionInfo *dims, int next_dim_size) {
    if (!dims) return create_dimension_list(next_dim_size);

    dims->num_dimensions++;
    dims->sizes = (int*)realloc(dims->sizes, dims->num_dimensions * sizeof(int));
    if (!dims->sizes) {
        perror("Cannot reallocate memory for dimension sizes");
        // if realloc fail, consider how to free exist dims
        exit(EXIT_FAILURE);
    }
    dims->sizes[dims->num_dimensions - 1] = next_dim_size;
    dims->total_elements *= next_dim_size;
    return dims;
}

void free_dimension_info(DimensionInfo *dims) {
    if (dims) {
        free(dims->sizes);
        free(dims);
    }
}

// create multi-dimensional array data
static void* create_md_array_recursive(const char* base_type, DimensionInfo *dims, int current_dim_idx) {
    if (current_dim_idx >= dims->num_dimensions) {
        return NULL; // should not reach here
    }

    int current_size = dims->sizes[current_dim_idx];
    if (current_dim_idx == dims->num_dimensions - 1) {
        // basic condition: set space for dara
        size_t element_size;
        if (strcmp(base_type, "int") == 0) element_size = sizeof(int);
        else if (strcmp(base_type, "float") == 0 || strcmp(base_type, "double") == 0) element_size = sizeof(float);
        else if (strcmp(base_type, "bool") == 0) element_size = sizeof(bool);
        else if (strcmp(base_type, "string") == 0 || strcmp(base_type, "char") == 0) element_size = sizeof(char*); // string use char*
        else {
            fprintf(stderr, "Not supported type: %s\n", base_type);
            return NULL;
        }
        void* data_segment = calloc(current_size, element_size); // use calloc to initialize to 0
        if (!data_segment) {
            perror("Cannot allocate memory for multi-dimensional array data");
            return NULL;
        }
        // for string/char array, if no additional init, then init as ""
        if (strcmp(base_type, "string") == 0 || strcmp(base_type, "char") == 0) {
            for (int i = 0; i < current_size; ++i) {
                ((char**)data_segment)[i] = strdup(""); // default ""
            }
        }
        return data_segment;
    } else {
        // recursive: set space for next pointed dimension
        void** pointers_segment = (void**)calloc(current_size, sizeof(void*));
        if (!pointers_segment) {
            perror("Cannot allocate memory for multi-dimensional array pointers");
            return NULL;
        }
        for (int i = 0; i < current_size; ++i) {
            pointers_segment[i] = create_md_array_recursive(base_type, dims, current_dim_idx + 1);
            if (!pointers_segment[i]) {
                // if one of the recursive call fails, free all previous allocations
                for (int j = 0; j < i; ++j) {
                    free_md_array_data(pointers_segment[j], base_type, dims, current_dim_idx + 1);
                }
                free(pointers_segment);
                return NULL;
            }
        }
        return pointers_segment;
    }
}

void* create_md_array_data(const char* base_type, DimensionInfo *dims) {
    if (!dims || dims->num_dimensions == 0) return NULL;
    return create_md_array_recursive(base_type, dims, 0);
}

// helper function to initialize multi-dimensional array data
static void initialize_md_array_recursive(void* current_segment, const char* base_type, DimensionInfo *dims, int current_dim_idx, Node** current_initializer) {
    if (!current_segment || current_dim_idx >= dims->num_dimensions) {
        return;
    }

    int current_size = dims->sizes[current_dim_idx];

    if (current_dim_idx == dims->num_dimensions - 1) { // real data
        for (int i = 0; i < current_size; ++i) {
            if (*current_initializer && (*current_initializer)->value) { // fi there's an initializer
                if (strcmp(base_type, "int") == 0) {
                    ((int*)current_segment)[i] = *(int*)((*current_initializer)->value);
                } else if (strcmp(base_type, "float") == 0 || strcmp(base_type, "double") == 0) {
                    ((float*)current_segment)[i] = *(float*)((*current_initializer)->value);
                } else if (strcmp(base_type, "bool") == 0) {
                    ((bool*)current_segment)[i] = *(bool*)((*current_initializer)->value);
                } else if (strcmp(base_type, "string") == 0 || strcmp(base_type, "char") == 0) {
                    free(((char**)current_segment)[i]); // free original ""
                    ((char**)current_segment)[i] = strdup((char*)((*current_initializer)->value));
                }
                *current_initializer = (*current_initializer)->next; // move to next initializer
            } else {
                // keep default value
            }
        }
    } else { // pointer dimension
        for (int i = 0; i < current_size; ++i) {
            initialize_md_array_recursive(((void**)current_segment)[i], base_type, dims, current_dim_idx + 1, current_initializer);
        }
    }
}


void initialize_md_array_data(void* array_data, const char* base_type, DimensionInfo *dims, Node* initializer_list) {
    if (!array_data || !dims) return;
    Node* current_init = initializer_list; // init list head
    initialize_md_array_recursive(array_data, base_type, dims, 0, &current_init);
}


void free_md_array_data(void* array_segment, const char* base_type, DimensionInfo *dims, int current_dim_idx) {
    if (!array_segment || !dims || current_dim_idx >= dims->num_dimensions) {
        return;
    }

    int current_size = dims->sizes[current_dim_idx];
    if (current_dim_idx == dims->num_dimensions - 1) {
        if (strcmp(base_type, "string") == 0 || strcmp(base_type, "char") == 0) {
            for (int i = 0; i < current_size; ++i) {
                free(((char**)array_segment)[i]); // free each string
            }
        }
        free(array_segment); // free segment
    } else { // pointer dimension
        for (int i = 0; i < current_size; ++i) {
            free_md_array_data(((void**)array_segment)[i], base_type, dims, current_dim_idx + 1);
        }
        free(array_segment); // free pointer segment
    }
}

int count_initializers(Node* init_list) {
    int count = 0;
    Node* current = init_list;
    while (current != NULL) {
        count++;
        current = current->next;
    }
    return count;
}


