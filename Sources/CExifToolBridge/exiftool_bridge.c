#include "exiftool_bridge.h"

#include <assert.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef TRUE
#undef TRUE
#endif

#ifdef FALSE
#undef FALSE
#endif

#include <EXTERN.h>
#include <perl.h>

extern char **environ;

struct exiftool_runtime {
    PerlInterpreter *interpreter;
    pthread_mutex_t lock;
    size_t session_count;
    char *module_root;
};

struct exiftool_session {
    exiftool_runtime_t *runtime;
    SV *tool_reference;
};

static pthread_once_t exiftool_perl_once = PTHREAD_ONCE_INIT;
static bool exiftool_perl_initialized = false;

static void exiftool_perl_init_once(void) {
    int argc = 1;
    char **argv = calloc(2, sizeof(char *));
    char **env = environ;

    assert(argv != NULL);
    argv[0] = "exiftool-bridge";
    PERL_SYS_INIT3(&argc, &argv, &env);
    exiftool_perl_initialized = true;
    free(argv);
}

static char *exiftool_copy_string(const char *source) {
    size_t length;
    char *copy;

    if (source == NULL) {
        return NULL;
    }

    length = strlen(source);
    copy = malloc(length + 1);
    assert(copy != NULL);
    memcpy(copy, source, length + 1);
    return copy;
}

static exiftool_result_t exiftool_make_result(
    exiftool_status_t status,
    const char *payload,
    const char *error_message
) {
    exiftool_result_t result;

    result.status = status;
    result.payload = exiftool_copy_string(payload);
    result.error_message = exiftool_copy_string(error_message);
    return result;
}

static char *exiftool_perl_quote(const char *source) {
    size_t index;
    size_t extra = 0;
    size_t length = strlen(source);
    char *quoted;
    size_t output_index = 0;

    for (index = 0; index < length; index += 1) {
        if (source[index] == '\\' || source[index] == '\'') {
            extra += 1;
        }
    }

    quoted = malloc(length + extra + 1);
    assert(quoted != NULL);

    for (index = 0; index < length; index += 1) {
        if (source[index] == '\\' || source[index] == '\'') {
            quoted[output_index] = '\\';
            output_index += 1;
        }
        quoted[output_index] = source[index];
        output_index += 1;
    }

    quoted[output_index] = '\0';
    return quoted;
}

static exiftool_result_t exiftool_eval_string(
    exiftool_runtime_t *runtime,
    const char *script,
    bool expect_payload
) {
    SV *value = NULL;
    const char *perl_error = NULL;

    PERL_SET_CONTEXT(runtime->interpreter);

    value = eval_pv(script, TRUE);
    perl_error = SvTRUE(ERRSV) ? SvPV_nolen(ERRSV) : NULL;

    if (perl_error != NULL && perl_error[0] != '\0') {
        return exiftool_make_result(EXIFTOOL_STATUS_PERL_ERROR, NULL, perl_error);
    }

    if (!expect_payload) {
        return exiftool_make_result(EXIFTOOL_STATUS_OK, NULL, NULL);
    }

    if (value == NULL) {
        return exiftool_make_result(
            EXIFTOOL_STATUS_INTERNAL_ERROR,
            NULL,
            "Perl eval returned a null scalar"
        );
    }

    return exiftool_make_result(EXIFTOOL_STATUS_OK, SvPV_nolen(value), NULL);
}

static exiftool_result_t exiftool_runtime_bootstrap(exiftool_runtime_t *runtime) {
    const char *template =
        "BEGIN {\n"
        "    require lib;\n"
        "    my $root = '%s/lib';\n"
        "    my @paths = ($root);\n"
        "    my $perl5_root = \"$root/perl5\";\n"
        "    if (opendir(my $versions, $perl5_root)) {\n"
        "        for my $version (readdir $versions) {\n"
        "            next if $version =~ /^\\./;\n"
        "            my $version_path = \"$perl5_root/$version\";\n"
        "            next unless -d $version_path;\n"
        "            push @paths, $version_path;\n"
        "            if (opendir(my $entries, $version_path)) {\n"
        "                for my $entry (readdir $entries) {\n"
        "                    next if $entry =~ /^\\./;\n"
        "                    my $entry_path = \"$version_path/$entry\";\n"
        "                    push @paths, $entry_path if -d $entry_path;\n"
        "                }\n"
        "                closedir $entries;\n"
        "            }\n"
        "        }\n"
        "        closedir $versions;\n"
        "    }\n"
        "    lib->import(@paths);\n"
        "}\n"
        "use strict;\n"
        "use warnings;\n"
        "use Image::ExifTool ();\n"
        "package ExifToolBridge;\n"
        "use strict;\n"
        "use warnings;\n"
        "sub _json_string {\n"
        "    my ($value) = @_;\n"
        "    $value = '' unless defined $value;\n"
        "    $value =~ s/\\\\/\\\\\\\\/g;\n"
        "    $value =~ s/\"/\\\\\"/g;\n"
        "    $value =~ s/\\r/\\\\r/g;\n"
        "    $value =~ s/\\n/\\\\n/g;\n"
        "    $value =~ s/\\t/\\\\t/g;\n"
        "    $value =~ s/([\\x00-\\x1f])/sprintf(\"\\\\u%04x\", ord($1))/ge;\n"
        "    return '\"' . $value . '\"';\n"
        "}\n"
        "sub _encode_json {\n"
        "    my ($value) = @_;\n"
        "    return 'null' unless defined $value;\n"
        "    my $reference_type = ref $value;\n"
        "    if (!$reference_type) {\n"
        "        return _json_string(\"$value\");\n"
        "    }\n"
        "    if ($reference_type eq 'ARRAY') {\n"
        "        return '[' . join(',', map { _encode_json($_) } @$value) . ']';\n"
        "    }\n"
        "    if ($reference_type eq 'HASH') {\n"
        "        return '{' . join(',', map { _json_string($_) . ':' . _encode_json($value->{$_}) } sort keys %%$value) . '}';\n"
        "    }\n"
        "    if ($reference_type eq 'SCALAR' || $reference_type eq 'REF') {\n"
        "        return _encode_json($$value);\n"
        "    }\n"
        "    return _json_string(\"$value\");\n"
        "}\n"
        "sub _parse_tags_payload {\n"
        "    my ($payload) = @_;\n"
        "    return () unless defined $payload && length($payload);\n"
        "    return grep { length($_) } split(/\\n/, $payload);\n"
        "}\n"
        "sub _decode_hex {\n"
        "    my ($payload) = @_;\n"
        "    return '' unless defined $payload && length($payload);\n"
        "    return pack('H*', $payload);\n"
        "}\n"
        "sub _parse_assignments_payload {\n"
        "    my ($payload) = @_;\n"
        "    my %%assignments;\n"
        "    return \\%%assignments unless defined $payload && length($payload);\n"
        "    for my $line (split(/\\n/, $payload)) {\n"
        "        my ($tag, $type, $value) = split(/\\t/, $line, 3);\n"
        "        die 'Malformed assignment payload' unless defined $tag && defined $type;\n"
        "        if ($type eq 's') {\n"
        "            $assignments{$tag} = _decode_hex($value);\n"
        "        } elsif ($type eq 'n') {\n"
        "            $assignments{$tag} = 0 + ($value // 0);\n"
        "        } elsif ($type eq 'b') {\n"
        "            $assignments{$tag} = ($value // '') eq '1' ? 1 : 0;\n"
        "        } elsif ($type eq 'z') {\n"
        "            $assignments{$tag} = undef;\n"
        "        } else {\n"
        "            die 'Unsupported assignment type';\n"
        "        }\n"
        "    }\n"
        "    return \\%%assignments;\n"
        "}\n"
        "sub create_tool {\n"
        "    return Image::ExifTool->new();\n"
        "}\n"
        "sub versions_json {\n"
        "    return '{\"exiftool\":' . _json_string($Image::ExifTool::VERSION) . ',\"perl\":' . _json_string($^V->normal) . '}';\n"
        "}\n"
        "sub read_metadata_json {\n"
        "    my ($tool, $path, $tags_payload) = @_;\n"
        "    my @tags = _parse_tags_payload($tags_payload);\n"
        "    my $info = @tags ? $tool->ImageInfo($path, @tags) : $tool->ImageInfo($path);\n"
        "    return _encode_json($info);\n"
        "}\n"
        "sub write_metadata_json {\n"
        "    my ($source_path, $destination_path, $assignments_payload) = @_;\n"
        "    my $tool = Image::ExifTool->new();\n"
        "    my $assignments = _parse_assignments_payload($assignments_payload);\n"
        "    for my $tag (sort keys %%$assignments) {\n"
        "        $tool->SetNewValue($tag, $assignments->{$tag});\n"
        "    }\n"
        "    my $success = defined($destination_path) && length($destination_path)\n"
        "        ? $tool->WriteInfo($source_path, $destination_path)\n"
        "        : $tool->WriteInfo($source_path);\n"
        "    my $error = $tool->GetValue('Error');\n"
        "    my $warning = $tool->GetValue('Warning');\n"
        "    my $result = '{\"success\":' . ($success ? 'true' : 'false');\n"
        "    $result .= ',\"error\":' . _json_string($error) if defined $error && length($error);\n"
        "    $result .= ',\"warning\":' . _json_string($warning) if defined $warning && length($warning);\n"
        "    $result .= '}';\n"
        "    return $result;\n"
        "}\n"
        "1;\n";
    char *quoted_root = NULL;
    size_t script_length = 0;
    char *script = NULL;
    exiftool_result_t result;

    quoted_root = exiftool_perl_quote(runtime->module_root);
    script_length = strlen(template) + strlen(quoted_root) + 32;
    script = malloc(script_length);
    assert(script != NULL);

    snprintf(script, script_length, template, quoted_root);
    result = exiftool_eval_string(runtime, script, false);

    free(script);
    free(quoted_root);
    return result;
}

static exiftool_result_t exiftool_call_string(
    exiftool_runtime_t *runtime,
    const char *function_name,
    SV **arguments,
    size_t argument_count
) {
    dSP;
    exiftool_result_t result = exiftool_make_result(EXIFTOOL_STATUS_INTERNAL_ERROR, NULL, "Unexpected Perl call state");
    const char *perl_error = NULL;
    SV *value = NULL;
    size_t index;
    int count;

    PERL_SET_CONTEXT(runtime->interpreter);

    ENTER;
    SAVETMPS;
    PUSHMARK(SP);

    for (index = 0; index < argument_count; index += 1) {
        XPUSHs(arguments[index]);
    }

    PUTBACK;
    count = call_pv(function_name, G_EVAL | G_SCALAR);
    SPAGAIN;

    perl_error = SvTRUE(ERRSV) ? SvPV_nolen(ERRSV) : NULL;
    if (perl_error != NULL && perl_error[0] != '\0') {
        result = exiftool_make_result(EXIFTOOL_STATUS_PERL_ERROR, NULL, perl_error);
        goto cleanup;
    }

    if (count != 1) {
        result = exiftool_make_result(
            EXIFTOOL_STATUS_INTERNAL_ERROR,
            NULL,
            "Perl call returned an unexpected stack size"
        );
        goto cleanup;
    }

    value = POPs;
    result = exiftool_make_result(EXIFTOOL_STATUS_OK, SvPV_nolen(value), NULL);

cleanup:
    PUTBACK;
    FREETMPS;
    LEAVE;
    return result;
}

static exiftool_result_t exiftool_call_reference(
    exiftool_runtime_t *runtime,
    const char *function_name,
    SV **arguments,
    size_t argument_count,
    SV **out_reference
) {
    dSP;
    const char *perl_error = NULL;
    SV *value = NULL;
    size_t index;
    int count;

    PERL_SET_CONTEXT(runtime->interpreter);
    *out_reference = NULL;

    ENTER;
    SAVETMPS;
    PUSHMARK(SP);

    for (index = 0; index < argument_count; index += 1) {
        XPUSHs(arguments[index]);
    }

    PUTBACK;
    count = call_pv(function_name, G_EVAL | G_SCALAR);
    SPAGAIN;

    perl_error = SvTRUE(ERRSV) ? SvPV_nolen(ERRSV) : NULL;
    if (perl_error != NULL && perl_error[0] != '\0') {
        PUTBACK;
        FREETMPS;
        LEAVE;
        return exiftool_make_result(EXIFTOOL_STATUS_PERL_ERROR, NULL, perl_error);
    }

    if (count != 1) {
        PUTBACK;
        FREETMPS;
        LEAVE;
        return exiftool_make_result(
            EXIFTOOL_STATUS_INTERNAL_ERROR,
            NULL,
            "Perl call returned an unexpected stack size"
        );
    }

    value = POPs;
    *out_reference = newSVsv(value);

    PUTBACK;
    FREETMPS;
    LEAVE;
    return exiftool_make_result(EXIFTOOL_STATUS_OK, NULL, NULL);
}

exiftool_result_t exiftool_runtime_create(
    const char *module_root,
    exiftool_runtime_t **out_runtime
) {
    exiftool_runtime_t *runtime = NULL;
    exiftool_result_t result;
    int argc = 3;
    char *argv[] = {
        "",
        "-e",
        "0",
        NULL
    };

    if (module_root == NULL || out_runtime == NULL) {
        return exiftool_make_result(
            EXIFTOOL_STATUS_INVALID_ARGUMENT,
            NULL,
            "module_root and out_runtime are required"
        );
    }

    pthread_once(&exiftool_perl_once, exiftool_perl_init_once);
    assert(exiftool_perl_initialized);

    runtime = calloc(1, sizeof(*runtime));
    assert(runtime != NULL);
    runtime->module_root = exiftool_copy_string(module_root);
    pthread_mutex_init(&runtime->lock, NULL);

    runtime->interpreter = perl_alloc();
    assert(runtime->interpreter != NULL);

    PERL_SET_CONTEXT(runtime->interpreter);
    perl_construct(runtime->interpreter);
    PL_exit_flags |= PERL_EXIT_DESTRUCT_END;

    if (perl_parse(runtime->interpreter, NULL, argc, argv, NULL) != 0) {
        result = exiftool_make_result(
            EXIFTOOL_STATUS_PERL_ERROR,
            NULL,
            SvPV_nolen(ERRSV)
        );
        perl_destruct(runtime->interpreter);
        perl_free(runtime->interpreter);
        pthread_mutex_destroy(&runtime->lock);
        free(runtime->module_root);
        free(runtime);
        return result;
    }

    if (perl_run(runtime->interpreter) != 0) {
        result = exiftool_make_result(
            EXIFTOOL_STATUS_PERL_ERROR,
            NULL,
            SvPV_nolen(ERRSV)
        );
        perl_destruct(runtime->interpreter);
        perl_free(runtime->interpreter);
        pthread_mutex_destroy(&runtime->lock);
        free(runtime->module_root);
        free(runtime);
        return result;
    }

    pthread_mutex_lock(&runtime->lock);
    result = exiftool_runtime_bootstrap(runtime);
    pthread_mutex_unlock(&runtime->lock);

    if (result.status != EXIFTOOL_STATUS_OK) {
        exiftool_result_destroy(result);
        perl_destruct(runtime->interpreter);
        perl_free(runtime->interpreter);
        pthread_mutex_destroy(&runtime->lock);
        free(runtime->module_root);
        free(runtime);
        return exiftool_make_result(
            EXIFTOOL_STATUS_PERL_ERROR,
            NULL,
            "Failed to bootstrap embedded ExifTool runtime"
        );
    }

    *out_runtime = runtime;
    return exiftool_make_result(EXIFTOOL_STATUS_OK, NULL, NULL);
}

void exiftool_runtime_destroy(exiftool_runtime_t *runtime) {
    if (runtime == NULL) {
        return;
    }

    assert(runtime->session_count == 0);

    pthread_mutex_lock(&runtime->lock);
    PERL_SET_CONTEXT(runtime->interpreter);
    perl_destruct(runtime->interpreter);
    perl_free(runtime->interpreter);
    pthread_mutex_unlock(&runtime->lock);

    pthread_mutex_destroy(&runtime->lock);
    free(runtime->module_root);
    free(runtime);
}

exiftool_result_t exiftool_runtime_versions_json(exiftool_runtime_t *runtime) {
    exiftool_result_t result;

    if (runtime == NULL) {
        return exiftool_make_result(
            EXIFTOOL_STATUS_INVALID_ARGUMENT,
            NULL,
            "runtime is required"
        );
    }

    pthread_mutex_lock(&runtime->lock);
    result = exiftool_call_string(runtime, "ExifToolBridge::versions_json", NULL, 0);
    pthread_mutex_unlock(&runtime->lock);
    return result;
}

exiftool_result_t exiftool_session_create(
    exiftool_runtime_t *runtime,
    exiftool_session_t **out_session
) {
    exiftool_session_t *session = NULL;
    exiftool_result_t result;

    if (runtime == NULL || out_session == NULL) {
        return exiftool_make_result(
            EXIFTOOL_STATUS_INVALID_ARGUMENT,
            NULL,
            "runtime and out_session are required"
        );
    }

    session = calloc(1, sizeof(*session));
    assert(session != NULL);
    session->runtime = runtime;

    pthread_mutex_lock(&runtime->lock);
    result = exiftool_call_reference(
        runtime,
        "ExifToolBridge::create_tool",
        NULL,
        0,
        &session->tool_reference
    );
    if (result.status == EXIFTOOL_STATUS_OK) {
        runtime->session_count += 1;
    }
    pthread_mutex_unlock(&runtime->lock);

    if (result.status != EXIFTOOL_STATUS_OK) {
        free(session);
        return result;
    }

    *out_session = session;
    return result;
}

void exiftool_session_destroy(exiftool_session_t *session) {
    exiftool_runtime_t *runtime;

    if (session == NULL) {
        return;
    }

    runtime = session->runtime;
    pthread_mutex_lock(&runtime->lock);
    PERL_SET_CONTEXT(runtime->interpreter);
    SvREFCNT_dec(session->tool_reference);
    runtime->session_count -= 1;
    pthread_mutex_unlock(&runtime->lock);
    free(session);
}

exiftool_result_t exiftool_session_read_metadata_json(
    exiftool_session_t *session,
    const char *file_path,
    const char *tags_json
) {
    exiftool_runtime_t *runtime;
    exiftool_result_t result;
    SV *arguments[3];

    if (session == NULL || file_path == NULL) {
        return exiftool_make_result(
            EXIFTOOL_STATUS_INVALID_ARGUMENT,
            NULL,
            "session and file_path are required"
        );
    }

    runtime = session->runtime;
    pthread_mutex_lock(&runtime->lock);

    arguments[0] = session->tool_reference;
    arguments[1] = sv_2mortal(newSVpv(file_path, 0));
    arguments[2] = tags_json == NULL ? &PL_sv_undef : sv_2mortal(newSVpv(tags_json, 0));

    result = exiftool_call_string(
        runtime,
        "ExifToolBridge::read_metadata_json",
        arguments,
        3
    );

    pthread_mutex_unlock(&runtime->lock);
    return result;
}

exiftool_result_t exiftool_session_write_metadata_json(
    exiftool_session_t *session,
    const char *source_path,
    const char *destination_path,
    const char *assignments_json
) {
    exiftool_runtime_t *runtime;
    exiftool_result_t result;
    SV *arguments[3];

    if (session == NULL || source_path == NULL || assignments_json == NULL) {
        return exiftool_make_result(
            EXIFTOOL_STATUS_INVALID_ARGUMENT,
            NULL,
            "session, source_path and assignments_json are required"
        );
    }

    runtime = session->runtime;
    pthread_mutex_lock(&runtime->lock);

    arguments[0] = sv_2mortal(newSVpv(source_path, 0));
    arguments[1] = destination_path == NULL ? &PL_sv_undef : sv_2mortal(newSVpv(destination_path, 0));
    arguments[2] = sv_2mortal(newSVpv(assignments_json, 0));

    result = exiftool_call_string(
        runtime,
        "ExifToolBridge::write_metadata_json",
        arguments,
        3
    );

    pthread_mutex_unlock(&runtime->lock);
    return result;
}

void exiftool_result_destroy(exiftool_result_t result) {
    free(result.payload);
    free(result.error_message);
}
