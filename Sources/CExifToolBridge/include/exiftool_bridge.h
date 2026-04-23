#ifndef EXIFTOOL_BRIDGE_H
#define EXIFTOOL_BRIDGE_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct exiftool_runtime exiftool_runtime_t;
typedef struct exiftool_session exiftool_session_t;

typedef enum exiftool_status {
    EXIFTOOL_STATUS_OK = 0,
    EXIFTOOL_STATUS_INVALID_ARGUMENT = 1,
    EXIFTOOL_STATUS_PERL_ERROR = 2,
    EXIFTOOL_STATUS_INTERNAL_ERROR = 3
} exiftool_status_t;

typedef struct exiftool_result {
    exiftool_status_t status;
    char *payload;
    char *error_message;
} exiftool_result_t;

exiftool_result_t exiftool_runtime_create(
    const char *module_root,
    exiftool_runtime_t **out_runtime
);

void exiftool_runtime_destroy(exiftool_runtime_t *runtime);

exiftool_result_t exiftool_runtime_versions_json(exiftool_runtime_t *runtime);

exiftool_result_t exiftool_session_create(
    exiftool_runtime_t *runtime,
    exiftool_session_t **out_session
);

void exiftool_session_destroy(exiftool_session_t *session);

exiftool_result_t exiftool_session_read_metadata_json(
    exiftool_session_t *session,
    const char *file_path,
    const char *tags_json
);

exiftool_result_t exiftool_session_write_metadata_json(
    exiftool_session_t *session,
    const char *source_path,
    const char *destination_path,
    const char *assignments_json
);

void exiftool_result_destroy(exiftool_result_t result);

#ifdef __cplusplus
}
#endif

#endif
