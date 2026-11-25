/* RV64 Linux guest: only the installed kernel UAPI headers are needed.
 * riscv64-linux-gnu-gcc -std=c11 -O2 -Wall -Wextra -static -o kms-test kms-test.c
 */
#include <drm/drm.h>
#include <drm/drm_mode.h>
#include <drm/drm_fourcc.h>
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <unistd.h>

enum { W = 640, H = 480 };
static int fd;

static void die(const char *what)
{
    perror(what);
    exit(EXIT_FAILURE);
}

static void check_ioctl(unsigned long cmd, void *arg, const char *what)
{
    int r;
    do { r = ioctl(fd, cmd, arg); } while (r < 0 && errno == EINTR);
    if (r < 0) die(what);
}
#define KMS(cmd, arg) check_ioctl(DRM_IOCTL_MODE_##cmd, (arg), #cmd)

static void *array(size_t count, size_t size)
{
    void *p = calloc(count ? count : 1, size);
    if (!p) die("calloc");
    return p;
}

static void select_output(struct drm_mode_crtc *crtc, uint32_t *connector)
{
    struct drm_mode_card_res r = {0};
    KMS(GETRESOURCES, &r);
    uint32_t nc = r.count_connectors, nr = r.count_crtcs;
    uint32_t *ids = array(nc, sizeof(*ids)), *crtcs = array(nr, sizeof(*crtcs));
    r.connector_id_ptr = (uintptr_t)ids;
    r.crtc_id_ptr = (uintptr_t)crtcs;
    r.count_fbs = r.count_encoders = 0;
    KMS(GETRESOURCES, &r);
    if (r.count_connectors > nc || r.count_crtcs > nr) {
        fputs("KMS topology changed during enumeration\n", stderr);
        exit(EXIT_FAILURE);
    }
    for (unsigned i = 0; i < r.count_connectors && !*connector; ++i) {
        struct drm_mode_get_connector c = { .connector_id = ids[i] };
        KMS(GETCONNECTOR, &c);
        /* UAPI encodes CONNECTED as 1 (the enum name is kernel-private). */
        if (c.connection != 1 || !c.count_modes || !c.count_encoders) continue;
        unsigned nm = c.count_modes, ne = c.count_encoders;
        struct drm_mode_modeinfo *modes = array(nm, sizeof(*modes));
        uint32_t *enc = array(ne, sizeof(*enc));
        c.modes_ptr = (uintptr_t)modes;
        c.encoders_ptr = (uintptr_t)enc;
        c.count_props = 0;
        KMS(GETCONNECTOR, &c);
        if (c.connection == 1 && c.count_modes <= nm && c.count_encoders <= ne) {
            unsigned m = 0;
            while (m < c.count_modes && (modes[m].hdisplay != W || modes[m].vdisplay != H)) ++m;
            for (unsigned e = 0; m < c.count_modes && e < c.count_encoders && !*connector; ++e) {
                struct drm_mode_get_encoder encoder = { .encoder_id = enc[e] };
                KMS(GETENCODER, &encoder);
                for (unsigned j = 0; j < r.count_crtcs && j < 32; ++j) {
                    if (!(encoder.possible_crtcs & (1u << j))) continue;
                    crtc->crtc_id = crtcs[j];
                    crtc->mode = modes[m];
                    *connector = ids[i];
                    break;
                }
            }
        }
        free(modes);
        free(enc);
    }
    free(ids);
    free(crtcs);
    if (!*connector) {
        fputs("No connected 640x480 output with compatible CRTC\n", stderr);
        exit(EXIT_FAILURE);
    }
}

/* Numeric XRGB8888 = 0x00RRGGBB, equivalent to B,G,R,0 bytes on RV64LE. */
static uint32_t pixel(unsigned x, unsigned y)
{
    return (((x + 3*y) & 255) << 16) | (((5*x + y) & 255) << 8) | ((x ^ (7*y)) & 255);
}

int main(int argc, char **argv)
{
    const char *path = argc > 1 ? argv[1] : "/dev/dri/card0";
    fd = open(path, O_RDWR);
    if (fd < 0) die(path);
    uint32_t connector = 0;
    struct drm_mode_crtc crtc = {0};
    select_output(&crtc, &connector);

    struct drm_mode_create_dumb bo = { .width = W, .height = H, .bpp = 32 };
    KMS(CREATE_DUMB, &bo);
    if (bo.pitch < W*4 || bo.pitch % 4 || bo.size < (uint64_t)bo.pitch * H) {
        fputs("Invalid dumb buffer layout\n", stderr);
        return EXIT_FAILURE;
    }
    struct drm_mode_map_dumb map = { .handle = bo.handle };
    KMS(MAP_DUMB, &map);
    uint8_t *mem = mmap(NULL, bo.size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, map.offset);
    if (mem == MAP_FAILED) die("mmap dumb buffer");

    /* The off-origin patch is initially wrong in every channel. Capturing
     * after DIRTYFB verifies that its update reached the scanout. */
    struct drm_clip_rect clip = { .x1 = 37, .y1 = 53, .x2 = 123, .y2 = 94 };
    for (unsigned y = 0; y < H; ++y) {
        uint32_t *row = (uint32_t *)(mem + y * (size_t)bo.pitch);
        for (unsigned x = 0; x < W; ++x) {
            int patch = x >= clip.x1 && x < clip.x2 && y >= clip.y1 && y < clip.y2;
            row[x] = pixel(x, y) ^ (patch ? 0xffffff : 0);
        }
    }
    struct drm_mode_fb_cmd2 fb = { .width = W, .height = H,
        .pixel_format = DRM_FORMAT_XRGB8888, .handles = {bo.handle}, .pitches = {bo.pitch} };
    KMS(ADDFB2, &fb);
    crtc.set_connectors_ptr = (uintptr_t)&connector;
    crtc.count_connectors = 1;
    crtc.fb_id = fb.fb_id;
    crtc.mode_valid = 1;
    KMS(SETCRTC, &crtc);
    for (unsigned y = clip.y1; y < clip.y2; ++y) {
        uint32_t *row = (uint32_t *)(mem + y * (size_t)bo.pitch);
        for (unsigned x = clip.x1; x < clip.x2; ++x) row[x] = pixel(x, y);
    }
    struct drm_mode_fb_dirty_cmd dirty = { .fb_id = fb.fb_id,
        .num_clips = 1, .clips_ptr = (uintptr_t)&clip };
    KMS(DIRTYFB, &dirty);
    puts("GLANDA-KMS-READY");
    fflush(stdout);
    for (;;) pause(); /* Keep DRM master and FB alive until killed after capture. */
}
