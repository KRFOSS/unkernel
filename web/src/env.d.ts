// SPDX-License-Identifier: MIT
// Copyright (C) 2026 Pooya Parsa <pooya@pi0.io>
// Build-time constants from vite.config.ts (define).

/** The About dialog's build details; empty strings where unknown. */
declare const __KW_BUILD__: {
	/** Linux release from the base bundle's banner (7.3.4+). */
	linux: string;
	/** The kernel's GitHub release tag (web/scripts/kernel.ts pageSource()), or "local" (a local build: KW_KERNEL, KW_DISTROS or auto-detected). */
	kernel: string;
	/** The page's commit hash and its date (ISO 8601). */
	commit: string;
	date: string;
};

/**
 * Optional build-time base answering the guest's Debian apt host (Vite define
 * from KW_DEB_MIRROR). Empty means this page's same-origin /deb, so one image
 * works on any host. A deployer may bake a fixed mirror at build time.
 */
declare const __KW_DEB_MIRROR__: string;

/**
 * The page's kernel and distro images (vite.config.ts, web/scripts/kernel.ts
 * pageSource()): the base bundle's UP kernel and its SMP one (null without
 * an SMP patch), the guest GL renderer's virgl.mjs (null without one; fetched
 * only with the GL option), the guest Vulkan renderer's kwvk-naga.wasm (null
 * without it; fetched only with the Vulkan option), and the images, debian first.
 */
declare module "virtual:unkernel-kernel" {
	export const kernelUrl: URL;
	export const kernelSmpUrl: URL | null;
	export const glUrl: URL | null;
	export const vkShaderUrl: URL | null;
	export const distros: { name: string; url: string; size: number; imageId?: string }[];
}
