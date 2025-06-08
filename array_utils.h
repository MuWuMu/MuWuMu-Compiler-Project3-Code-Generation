#ifndef ARRAY_UTILS_H
#define ARRAY_UTILS_H

#include <stdbool.h>

// pre-declare Node structure for initializer list
struct Node;
// pre-declare Symbol structure for array access
struct Symbol;

// store dimension information
typedef struct DimensionInfo {
    int num_dimensions;
    int *sizes;            // pointer to array of each dimension size
    long total_elements;
} DimensionInfo;

// for array value access in expression
typedef struct IndexAccessInfo {
    int num_indices;
    int *indices;
} IndexAccessInfo;

DimensionInfo* create_dimension_list(int first_dim_size);
DimensionInfo* add_dimension_to_list(DimensionInfo *dims, int next_dim_size);
void free_dimension_info(DimensionInfo *dims);

// returned void* is pointer to the array data
void* create_md_array_data(const char* base_type, DimensionInfo *dims);
void initialize_md_array_data(void* array_data, const char* base_type, DimensionInfo *dims, struct Node* initializer_list);
void free_md_array_data(void* array_data, const char* base_type, DimensionInfo *dims, int current_dim);

// counter helper function
int count_initializers(struct Node* init_list);

#endif // ARRAY_UTILS_H