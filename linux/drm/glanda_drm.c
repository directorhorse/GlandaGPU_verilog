// SPDX-License-Identifier: GPL-2.0-only
/* Atomic KMS for the GlandaGPU Avalon framebuffer (OF platform device). */
#include <linux/io.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/platform_device.h>

#include <drm/drm_atomic.h>
#include <drm/drm_atomic_helper.h>
#include <drm/drm_damage_helper.h>
#include <drm/drm_drv.h>
#include <drm/drm_framebuffer.h>
#include <drm/drm_gem_atomic_helper.h>
#include <drm/drm_gem_framebuffer_helper.h>
#include <drm/drm_gem_shmem_helper.h>
#include <drm/drm_modeset_helper_vtables.h>
#include <drm/drm_probe_helper.h>
#include <drm/drm_simple_kms_helper.h>

#define GLANDA_WIDTH	640
#define GLANDA_HEIGHT	480
#define GLANDA_BYTES	(GLANDA_WIDTH * GLANDA_HEIGHT * sizeof(u32))

struct glanda_device {
	struct drm_device drm;
	struct drm_simple_display_pipe pipe;
	struct drm_connector connector;
	u32 __iomem *pixels;
	/* Used only in serialized commit tails for the single CRTC. */
	__le32 row[GLANDA_WIDTH];
};

static const struct drm_display_mode glanda_mode = {
	DRM_MODE("640x480", DRM_MODE_TYPE_DRIVER, 25000,
		 640, 656, 752, 800, 0, 480, 490, 492, 525, 0,
		 DRM_MODE_FLAG_NHSYNC | DRM_MODE_FLAG_NVSYNC),
};

static int glanda_get_modes(struct drm_connector *connector)
{
	return drm_connector_helper_get_modes_fixed(connector, &glanda_mode);
}

static const struct drm_connector_helper_funcs glanda_connector_helpers = {
	.get_modes = glanda_get_modes,
};

static const struct drm_connector_funcs glanda_connector_funcs = {
	.reset = drm_atomic_helper_connector_reset,
	.fill_modes = drm_helper_probe_single_connector_modes,
	.destroy = drm_connector_cleanup,
	.atomic_duplicate_state = drm_atomic_helper_connector_duplicate_state,
	.atomic_destroy_state = drm_atomic_helper_connector_destroy_state,
};

static enum drm_mode_status glanda_mode_valid(struct drm_simple_display_pipe *pipe,
					     const struct drm_display_mode *mode)
{
	return drm_mode_equal(mode, &glanda_mode) ? MODE_OK : MODE_BAD;
}

static void glanda_blit(struct drm_simple_display_pipe *pipe,
			struct drm_plane_state *state, struct drm_rect clip)
{
	struct glanda_device *gdev = container_of(pipe, struct glanda_device, pipe);
	struct drm_shadow_plane_state *shadow = to_drm_shadow_plane_state(state);
	struct drm_framebuffer *fb = state->fb;
	const struct drm_rect screen = DRM_RECT_INIT(0, 0, GLANDA_WIDTH, GLANDA_HEIGHT);
	int x, y, idx, ret;

	if (!fb || !drm_rect_intersect(&clip, &screen))
		return;
	if (!drm_dev_enter(&gdev->drm, &idx))
		return;

	ret = drm_gem_fb_begin_cpu_access(fb, DMA_FROM_DEVICE);
	if (ret) {
		drm_err_ratelimited(&gdev->drm, "shadow CPU access failed: %d\n", ret);
		goto out;
	}

	/* data[0] includes the FB offset; the GEM FB helper validates its
	 * object size. Source rows may have padding; VRAM rows never do.
	 */
	for (y = clip.y1; y < clip.y2; y++) {
		size_t off = (size_t)y * fb->pitches[0] + clip.x1 * sizeof(__le32);
		u32 __iomem *dst = gdev->pixels + y * GLANDA_WIDTH + clip.x1;

		iosys_map_memcpy_from(gdev->row, &shadow->data[0], off,
				      drm_rect_width(&clip) * sizeof(__le32));
		for (x = 0; x < drm_rect_width(&clip); x++) {
			u32 p = le32_to_cpu(gdev->row[x]);

			/* 0x00RRGGBB -> 0x00000RGB. The slave accepts only
			 * aligned, full-word writes, including for blanking.
			 */
			writel(((p >> 12) & 0xf00) | ((p >> 8) & 0x0f0) |
			       ((p >> 4) & 0x00f), dst + x);
		}
	}
	drm_gem_fb_end_cpu_access(fb, DMA_FROM_DEVICE);
out:
	drm_dev_exit(idx);
}

static void glanda_enable(struct drm_simple_display_pipe *pipe,
			  struct drm_crtc_state *crtc_state,
			  struct drm_plane_state *plane_state)
{
	struct drm_rect full = DRM_RECT_INIT(0, 0, GLANDA_WIDTH, GLANDA_HEIGHT);

	/* First modeset and re-enable must ignore partial damage. */
	glanda_blit(pipe, plane_state, full);
}

static void glanda_update(struct drm_simple_display_pipe *pipe,
			  struct drm_plane_state *old_state)
{
	struct drm_plane_state *state = pipe->plane.state;
	struct drm_crtc_state *crtc_state = pipe->crtc.state;
	struct drm_rect clip;

	/* The default commit tail calls enable after updating planes. */
	if (!crtc_state->active || drm_atomic_crtc_needs_modeset(crtc_state))
		return;
	if (state->fb && drm_atomic_helper_damage_merged(old_state, state, &clip))
		glanda_blit(pipe, state, clip);
}

static void glanda_disable(struct drm_simple_display_pipe *pipe)
{
	struct glanda_device *gdev = container_of(pipe, struct glanda_device, pipe);
	int i, idx;

	if (!drm_dev_enter(&gdev->drm, &idx))
		return;
	for (i = 0; i < GLANDA_WIDTH * GLANDA_HEIGHT; i++)
		writel(0, gdev->pixels + i);
	drm_dev_exit(idx);
}

static const struct drm_simple_display_pipe_funcs glanda_pipe_funcs = {
	.mode_valid = glanda_mode_valid,
	.enable = glanda_enable,
	.update = glanda_update,
	.disable = glanda_disable,
	DRM_GEM_SIMPLE_DISPLAY_PIPE_SHADOW_PLANE_FUNCS,
};

/* No vblank source: the default atomic helper tail completes flip events
 * after the synchronous VRAM copy. No IRQ, timer or scanout timestamp.
 */
static const struct drm_mode_config_funcs glanda_mode_config_funcs = {
	.fb_create = drm_gem_fb_create_with_dirty,
	.atomic_check = drm_atomic_helper_check,
	.atomic_commit = drm_atomic_helper_commit,
};

DEFINE_DRM_GEM_FOPS(glanda_fops);

static const struct drm_driver glanda_driver = {
	.driver_features = DRIVER_MODESET | DRIVER_GEM | DRIVER_ATOMIC,
	.fops = &glanda_fops,
	DRM_GEM_SHMEM_DRIVER_OPS,
	.name = "glandakms",
	.desc = "GlandaGPU platform KMS",
	.date = "20261125",
	.major = 1,
	.minor = 0,
};

static int glanda_probe(struct platform_device *pdev)
{
	static const u32 formats[] = { DRM_FORMAT_XRGB8888 };
	static const u64 modifiers[] = { DRM_FORMAT_MOD_LINEAR, DRM_FORMAT_MOD_INVALID };
	struct resource *res = platform_get_resource(pdev, IORESOURCE_MEM, 0);
	struct resource vram;
	struct glanda_device *gdev;
	struct drm_device *drm;
	int ret;

	if (!res || !IS_ALIGNED(res->start, sizeof(u32)) || res->end < res->start ||
	    res->end - res->start < GLANDA_BYTES - 1)
		return dev_err_probe(&pdev->dev, -EINVAL, "invalid VRAM resource\n");

	gdev = devm_drm_dev_alloc(&pdev->dev, &glanda_driver, struct glanda_device, drm);
	if (IS_ERR(gdev))
		return PTR_ERR(gdev);
	drm = &gdev->drm;
	/* Map only visible VRAM, not the command registers at +0x200000. */
	vram = *res;
	vram.end = vram.start + GLANDA_BYTES - 1;
	gdev->pixels = devm_ioremap_resource(&pdev->dev, &vram);
	if (IS_ERR(gdev->pixels))
		return PTR_ERR(gdev->pixels);

	ret = drmm_mode_config_init(drm);
	if (ret)
		return ret;
	drm->mode_config.funcs = &glanda_mode_config_funcs;
	drm->mode_config.min_width = drm->mode_config.max_width = GLANDA_WIDTH;
	drm->mode_config.min_height = drm->mode_config.max_height = GLANDA_HEIGHT;
	drm->mode_config.preferred_depth = 24;

	ret = drm_connector_init(drm, &gdev->connector, &glanda_connector_funcs,
				 DRM_MODE_CONNECTOR_VIRTUAL);
	if (ret)
		return ret;
	drm_connector_helper_add(&gdev->connector, &glanda_connector_helpers);
	ret = drm_simple_display_pipe_init(drm, &gdev->pipe, &glanda_pipe_funcs,
					   formats, ARRAY_SIZE(formats), modifiers,
					   &gdev->connector);
	if (ret)
		return ret;
	drm_plane_enable_fb_damage_clips(&gdev->pipe.plane);
	drm_mode_config_reset(drm);
	platform_set_drvdata(pdev, drm);
	return drm_dev_register(drm, 0);
}

static int glanda_remove(struct platform_device *pdev)
{
	struct drm_device *drm = platform_get_drvdata(pdev);

	drm_dev_unplug(drm);
	drm_atomic_helper_shutdown(drm);
	return 0;
}

static void glanda_shutdown(struct platform_device *pdev)
{
	drm_atomic_helper_shutdown(platform_get_drvdata(pdev));
}

static const struct of_device_id glanda_of_match[] = {
	{ .compatible = "glanda,gpu" },
	{ }
};
MODULE_DEVICE_TABLE(of, glanda_of_match);

static struct platform_driver glanda_platform_driver = {
	.probe = glanda_probe,
	.remove = glanda_remove,
	.shutdown = glanda_shutdown,
	.driver = {
		.name = "glanda_drm",
		.of_match_table = glanda_of_match,
	},
};
module_platform_driver(glanda_platform_driver);

MODULE_DESCRIPTION("GlandaGPU platform atomic KMS driver");
MODULE_LICENSE("GPL");
