#include <jni.h>
#include <stdlib.h>
#include <string.h>

int gifsicle_main(int argc, char **argv);

JNIEXPORT jint JNICALL
Java_com_example_gifsicle_GifsicleBridge_run(
    JNIEnv *env,
    jobject thiz,
    jobjectArray args
) {
    (void)thiz;

    jsize count = (*env)->GetArrayLength(env, args);
    int argc = (int)count + 1;

    char **argv = (char **)calloc((size_t)argc + 1, sizeof(char *));
    if (argv == NULL) return -1;

    argv[0] = strdup("gifsicle");
    if (argv[0] == NULL) {
        free(argv);
        return -1;
    }

    for (jsize i = 0; i < count; ++i) {
        jstring jarg = (jstring)(*env)->GetObjectArrayElement(env, args, i);
        const char *utf = (*env)->GetStringUTFChars(env, jarg, NULL);
        if (utf == NULL) {
            for (int k = 0; k <= i; ++k) free(argv[k]);
            free(argv);
            return -1;
        }
        argv[i + 1] = strdup(utf);
        (*env)->ReleaseStringUTFChars(env, jarg, utf);
        (*env)->DeleteLocalRef(env, jarg);
        if (argv[i + 1] == NULL) {
            for (int k = 0; k <= i; ++k) free(argv[k]);
            free(argv);
            return -1;
        }
    }

    int rc = gifsicle_main(argc, argv);

    for (int i = 0; i < argc; ++i) free(argv[i]);
    free(argv);
    return (jint)rc;
}
