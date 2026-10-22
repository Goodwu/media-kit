#include <mpv/client.h>

#include <stdlib.h>
#include <string.h>

enum fixture_mode {
    FIXTURE_NORMAL = 0,
    FIXTURE_ERROR = 1,
    FIXTURE_WRONG_COUNT = 2,
    FIXTURE_WRONG_ROOT_TYPE = 3,
    FIXTURE_WRONG_ITEM_TYPE = 4,
};

static int current_mode;
static int scalar_calls;
static int batch_calls;
static int node_contents_calls;
static int allocated_objects;
static int freed_objects;

static void *tracked_malloc(size_t size)
{
    void *value = malloc(size);
    if (value)
        allocated_objects++;
    return value;
}

static char *tracked_string(const char *value)
{
    size_t size = strlen(value) + 1;
    char *copy = tracked_malloc(size);
    if (copy)
        memcpy(copy, value, size);
    return copy;
}

static void tracked_free(void *value)
{
    if (value) {
        freed_objects++;
        free(value);
    }
}

static const char *property_value(const char *name)
{
    if (!strcmp(name, "missing"))
        return NULL;
    if (!strcmp(name, "empty"))
        return "";
    if (!strcmp(name, "unicode"))
        return "Dolby Vision \xF0\x9F\x8E\x9E";
    return name;
}

void fixture_reset(int mode)
{
    current_mode = mode;
    scalar_calls = 0;
    batch_calls = 0;
    node_contents_calls = 0;
    allocated_objects = 0;
    freed_objects = 0;
}

int fixture_scalar_calls(void) { return scalar_calls; }
int fixture_batch_calls(void) { return batch_calls; }
int fixture_node_contents_calls(void) { return node_contents_calls; }
int fixture_allocated_objects(void) { return allocated_objects; }
int fixture_freed_objects(void) { return freed_objects; }

char *mpv_get_property_string(mpv_handle *ctx, const char *name)
{
    (void)ctx;
    scalar_calls++;
    const char *value = property_value(name);
    return value ? tracked_string(value) : NULL;
}

void mpv_free(void *value)
{
    tracked_free(value);
}

void mpv_free_node_contents(mpv_node *node)
{
    node_contents_calls++;
    if (node->format == MPV_FORMAT_STRING) {
        tracked_free(node->u.string);
    } else if ((node->format == MPV_FORMAT_NODE_ARRAY ||
                node->format == MPV_FORMAT_NODE_MAP) && node->u.list) {
        mpv_node_list *list = node->u.list;
        for (int i = 0; i < list->num; i++) {
            if (list->values[i].format == MPV_FORMAT_STRING)
                tracked_free(list->values[i].u.string);
        }
        tracked_free(list->values);
        tracked_free(list);
    }
    node->format = MPV_FORMAT_NONE;
    node->u.list = NULL;
}

static void fill_array(const char *const *names, int count, mpv_node *result,
                       int item_type)
{
    int output_count = current_mode == FIXTURE_WRONG_COUNT ? count - 1 : count;
    mpv_node_list *list = tracked_malloc(sizeof(*list));
    mpv_node *values = output_count > 0
                           ? tracked_malloc(sizeof(*values) * output_count)
                           : NULL;
    if (output_count > 0)
        memset(values, 0, sizeof(*values) * output_count);
    list->num = output_count;
    list->values = values;
    list->keys = NULL;
    result->format = MPV_FORMAT_NODE_ARRAY;
    result->u.list = list;
    for (int i = 0; i < output_count; i++) {
        if (item_type && i == 0) {
            values[i].format = MPV_FORMAT_INT64;
            values[i].u.int64 = 23;
            continue;
        }
        const char *value = property_value(names[i]);
        if (!value) {
            values[i].format = MPV_FORMAT_NONE;
        } else {
            values[i].format = MPV_FORMAT_STRING;
            values[i].u.string = tracked_string(value);
        }
    }
}

int mpv_mediakit_get_property_strings(mpv_handle *ctx,
                                      const char *const *names, int count,
                                      mpv_node *result)
{
    (void)ctx;
    batch_calls++;
    result->format = MPV_FORMAT_NONE;
    result->u.list = NULL;
    if (current_mode == FIXTURE_WRONG_ROOT_TYPE) {
        result->format = MPV_FORMAT_STRING;
        result->u.string = tracked_string("bad-root");
        return 0;
    }
    fill_array(names, count, result,
               current_mode == FIXTURE_WRONG_ITEM_TYPE);
    return current_mode == FIXTURE_ERROR ? -5 : 0;
}
