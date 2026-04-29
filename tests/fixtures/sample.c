#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_SIZE 100

char password[] = "hardcoded_password_value";
char secret_key[] = "my_secret_key_12345678";

void unsafe_string_ops(char *input) {
    char buffer[MAX_SIZE];
    strcpy(buffer, input);
    strcat(buffer, " appended");
    sprintf(buffer, "%s", input);
    gets(buffer);
}

void format_string_vuln(char *user_input) {
    printf(user_input);
}

void insecure_random() {
    int token = rand();
    printf("Token: %d\n", token);
}

void malloc_without_check() {
    int *data = malloc(sizeof(int) * 100);
    data[0] = 42;
    free(data);
}

void deeply_nested_function(int **matrix, int rows, int cols) {
    for (int i = 0; i < rows; i++) {
        if (matrix[i] != NULL) {
            for (int j = 0; j < cols; j++) {
                if (matrix[i][j] > 0) {
                    for (int k = 0; k < matrix[i][j]; k++) {
                        if (k % 2 == 0) {
                            printf("Value: %d\n", k);
                        }
                    }
                }
            }
        }
    }
}

// TODO: add proper error handling
// FIXME: memory leak in edge case

void very_long_line_that_exceeds_the_maximum_allowed_line_length_of_one_hundred_and_twenty_characters_and_should_be_flagged_by_the_linter() {
    return;
}

int main() {
    char input[256];
    unsafe_string_ops(input);
    format_string_vuln(input);
    insecure_random();
    malloc_without_check();
    return 0;
}
