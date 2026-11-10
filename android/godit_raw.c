/* Puente minimo para leer fotos RAW con LibRaw desde Python (ctypes) en Android.
 * Devuelve la foto revelada como RGB de 16 bits con el balance de blancos de la camara, sRGB y recuperacion de luces,
 * igual que rawpy.postprocess(use_camera_wb=True, output_bps=16, output_color=sRGB, highlight_mode=Blend, auto_bright_thr=0.002). */
#include <libraw/libraw.h>
#include <stdlib.h>
#include <string.h>

int godit_raw_leer(const char *ruta, unsigned short **datos, int *ancho, int *alto) {
    libraw_data_t *lr = libraw_init(0);
    if (!lr) return -1;
    int r = libraw_open_file(lr, ruta);
    if (r != LIBRAW_SUCCESS) { libraw_close(lr); return r; }
    r = libraw_unpack(lr);
    if (r != LIBRAW_SUCCESS) { libraw_close(lr); return r; }
    lr->params.use_camera_wb = 1;
    lr->params.output_bps = 16;
    lr->params.output_color = 1;      /* sRGB */
    lr->params.highlight = 2;         /* mezclar luces */
    lr->params.auto_bright_thr = 0.002f;
    r = libraw_dcraw_process(lr);
    if (r != LIBRAW_SUCCESS) { libraw_close(lr); return r; }
    int err = 0;
    libraw_processed_image_t *img = libraw_dcraw_make_mem_image(lr, &err);
    if (!img || img->colors != 3 || img->bits != 16) {
        if (img) libraw_dcraw_clear_mem(img);
        libraw_close(lr);
        return err ? err : -2;
    }
    size_t n = (size_t)img->width * img->height * 3 * sizeof(unsigned short);
    *datos = (unsigned short *)malloc(n);
    if (!*datos) { libraw_dcraw_clear_mem(img); libraw_close(lr); return -3; }
    memcpy(*datos, img->data, n);
    *ancho = img->width;
    *alto = img->height;
    libraw_dcraw_clear_mem(img);
    libraw_close(lr);
    return 0;
}

void godit_raw_liberar(unsigned short *p) { free(p); }
