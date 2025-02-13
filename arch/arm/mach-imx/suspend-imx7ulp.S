/*
 * Copyright (C) 2016 Freescale Semiconductor, Inc.
 * Copyright 2017 NXP
 *
 * The code contained herein is licensed under the GNU General Public
 * License. You may obtain a copy of the GNU General Public License
 * Version 2 or later at the following locations:
 *
 * http://www.opensource.org/licenses/gpl-license.html
 * http://www.gnu.org/copyleft/gpl.html
 */

#include <linux/linkage.h>
#include <asm/asm-offsets.h>
#include "hardware.h"

.arch armv7-a

/*
 * ==================== low level suspend ====================
 *
 * Better to follow below rules to use ARM registers:
 * r0: pm_info structure address;
 *
 * suspend ocram space layout:
 * ======================== high address ======================
 *                              .
 *                              .
 *                              .
 *                              ^
 *                              ^
 *                              ^
 *                      imx7ulp_suspend code
 *              PM_INFO structure(imx7ulp_cpu_pm_info)
 * ======================== low address =======================
 */

/*
 * Below offsets are based on struct imx7ulp_cpu_pm_info
 * which defined in arch/arm/mach-imx/pm-imx7ulp.c, this
 * structure contains necessary pm info for low level
 * suspend related code.
 */
#define PM_INFO_M4_RESERVE0_OFFSET		0x0
#define PM_INFO_M4_RESERVE1_OFFSET		0x4
#define PM_INFO_M4_RESERVE2_OFFSET		0x8
#define PM_INFO_PBASE_OFFSET			0xc
#define PM_INFO_RESUME_ADDR_OFFSET		0x10
#define PM_INFO_PM_INFO_SIZE_OFFSET		0x14
#define PM_INFO_PM_INFO_SIM_VBASE_OFFSET	0x18
#define PM_INFO_PM_INFO_SCG1_VBASE_OFFSET	0x1c
#define PM_INFO_PM_INFO_MMDC_VBASE_OFFSET	0x20
#define PM_INFO_PM_INFO_MMDC_IO_VBASE_OFFSET	0x24
#define PM_INFO_PM_INFO_SMC1_VBASE_OFFSET	0x28
#define PM_INFO_PM_INFO_SCG1_VAL_OFFSET		0x2c
#define PM_INFO_MX7ULP_TTBR1_V_OFFSET		0x70
#define PM_INFO_MX7ULP_GPIO_REG_OFFSET		0x74
#define PM_INFO_IOMUX_NUM_OFFSET		0x94
#define PM_INFO_IOMUX_VAL_OFFSET		0x98
#define PM_INFO_SELECT_INPUT_NUM_OFFSET		0x268
#define PM_INFO_SELECT_INPUT_VAL_OFFSET		0x26c
#define PM_INFO_MMDC_IO_NUM_OFFSET		0x3a4
#define PM_INFO_MMDC_IO_VAL_OFFSET		0x3a8
/* below offsets depends on MX7ULP_MAX_MMDC_IO_NUM(36) definition */
#define PM_INFO_MMDC_NUM_OFFSET			0x5a8
#define PM_INFO_MMDC_VAL_OFFSET			0x5ac

#define DGO_CTRL0	0x50
#define DGO_GPR3	0x60
#define DGO_GPR4	0x64

#define MX7ULP_MMDC_MISC	0x18
#define MX7ULP_MMDC_MAPSR	0x404
#define MX7ULP_MMDC_MPDGCTRL0	0x83c

#define SCG_RCCR	0x14
#define SCG_DDRCCR	0x30
#define SCG_NICCCR	0x40
#define SCG_FIRCDIV	0x304
#define SCG_APLLCSR	0x500
#define SCG_APLLDIV	0x504
#define SCG_APLLCFG	0x508
#define SCG_APLLPFD	0x50c
#define SCG_APLLNUM	0x510
#define SCG_APLLDENOM	0x514
#define SCG_SPLLCSR	0x600
#define SCG_SPLLDIV	0x604
#define SCG_SPLLCFG	0x608
#define SCG_SPLLPFD	0x60c
#define SCG_SPLLNUM	0x610
#define SCG_SPLLDENOM	0x614
#define SCG_SOSCDIV	0x104

#define PMC1_CTRL	0x24

#define GPIO_PDOR		0x0
#define GPIO_PDDR		0x14
#define GPIO_PORT_NUM		0x4
#define GPIO_PORT_OFFSET	0x40

#define PMCTRL		0x10

#define IOMUX_OFFSET		0x0
#define SELECT_INPUT_OFFSET	0x200

	.align 3

	.macro store_ttbr1

	/* Store TTBR1 to pm_info->ttbr1 */
	mrc	p15, 0, r7, c2, c0, 1
	str	r7, [r0, #PM_INFO_MX7ULP_TTBR1_V_OFFSET]

	/* Disable Branch Prediction, Z bit in SCTLR. */
	mrc	p15, 0, r6, c1, c0, 0
	bic	r6, r6, #0x800
	mcr	p15, 0, r6, c1, c0, 0

	/* Flush the BTAC. */
	ldr	r6, =0x0
	mcr	p15, 0, r6, c7, c1, 6

	ldr	r6, =iram_tlb_phys_addr
	ldr	r6, [r6]
	dsb
	isb

	/* Store the IRAM table in TTBR1 */
	mcr	p15, 0, r6, c2, c0, 1
	/* Read TTBCR and set PD0=1, N = 1 */
	mrc	p15, 0, r6, c2, c0, 2
	orr	r6, r6, #0x11
	mcr	p15, 0, r6, c2, c0, 2

	dsb
	isb

	/* flush the TLB */
	ldr	r6, =0x0
	mcr	p15, 0, r6, c8, c3, 0

	.endm

	.macro restore_ttbr1

	/* Enable L1 data cache. */
	mrc	p15, 0, r6, c1, c0, 0
	orr	r6, r6, #0x4
	mcr	p15, 0, r6, c1, c0, 0

	dsb
	isb

	/* Restore TTBCR */
	/* Read TTBCR and set PD0=0, N = 0 */
	mrc	p15, 0, r6, c2, c0, 2
	bic	r6, r6, #0x11
	mcr	p15, 0, r6, c2, c0, 2
	dsb
	isb

	/* flush the TLB */
	ldr	r6, =0x0
	mcr	p15, 0, r6, c8, c3, 0

	/* Enable Branch Prediction, Z bit in SCTLR. */
	mrc	p15, 0, r6, c1, c0, 0
	orr	r6, r6, #0x800
	mcr	p15, 0, r6, c1, c0, 0

	/* Flush the Branch Target Address Cache (BTAC) */
	ldr	r6, =0x0
	mcr	p15, 0, r6, c7, c1, 6

	/* Restore TTBR1, get the origin ttbr1 from pm info */
	ldr	r7, [r0, #PM_INFO_MX7ULP_TTBR1_V_OFFSET]
	mcr	p15, 0, r7, c2, c0, 1

	.endm

	.macro	disable_l1_dcache

	/*
	 * Flush all data from the L1 data cache before disabling
	 * SCTLR.C bit.
	 */
	push	{r0 - r10, lr}
	ldr	r7, =v7_flush_dcache_all
	mov	lr, pc
	mov	pc, r7
	pop	{r0 - r10, lr}

	/* disable d-cache */
	mrc	p15, 0, r7, c1, c0, 0
	bic	r7, r7, #(1 << 2)
	mcr	p15, 0, r7, c1, c0, 0
	dsb
	isb

	push	{r0 - r10, lr}
	ldr	r7, =v7_flush_dcache_all
	mov	lr, pc
	mov	pc, r7
	pop	{r0 - r10, lr}

	.endm

	.macro	restore_mmdc_settings

	ldr	r10, =MX7ULP_MMDC_IO_BASE_ADDR
	ldr	r11, =MX7ULP_MMDC_BASE_ADDR

	/* resume mmdc iomuxc settings */
	ldr	r6, [r0, #PM_INFO_MMDC_IO_NUM_OFFSET]
	ldr	r7, =PM_INFO_MMDC_IO_VAL_OFFSET
	add	r7, r7, r0
11:
	ldr	r8, [r7], #0x4
	ldr	r9, [r7], #0x4
	str	r9, [r10, r8]
	subs	r6, r6, #0x1
	bne	11b

	/* restore MMDC settings */
	ldr	r6, [r0, #PM_INFO_MMDC_NUM_OFFSET]
	ldr	r7, =PM_INFO_MMDC_VAL_OFFSET
	add	r7, r7, r0
1:
	ldr	r8, [r7], #0x4
	ldr	r9, [r7], #0x4
	str	r9, [r11, r8]
	subs	r6, r6, #0x1
	bne	1b

	/* let DDR enter self-refresh */
	ldr	r7, [r11, #MX7ULP_MMDC_MAPSR]
	orr	r7, r7, #(1 << 20)
	str	r7, [r11, #MX7ULP_MMDC_MAPSR]
2:
	ldr	r7, [r11, #MX7ULP_MMDC_MAPSR]
	ands	r7, r7, #(1 << 24)
	beq	2b

	/* let DDR out of self-refresh */
	ldr	r7, [r11, #MX7ULP_MMDC_MAPSR]
	bic	r7, r7, #(1 << 20)
	str	r7, [r11, #MX7ULP_MMDC_MAPSR]
3:
	ldr	r7, [r11, #MX7ULP_MMDC_MAPSR]
	ands	r7, r7, #(1 << 24)
	bne	3b

	/* kick off MMDC */
	ldr	r4, =0x0
	str	r4, [r11, #0x1c]

	/* let DDR out of self-refresh */
	ldr	r7, [r11, #MX7ULP_MMDC_MAPSR]
	bic	r7, r7, #(1 << 20)
	str	r7, [r11, #MX7ULP_MMDC_MAPSR]
4:
	ldr	r7, [r11, #MX7ULP_MMDC_MAPSR]
	ands	r7, r7, #(1 << 24)
	bne	4b

	/* enable DDR auto power saving */
	ldr	r7, [r11, #MX7ULP_MMDC_MAPSR]
	bic	r7, r7, #0x1
	str	r7, [r11, #MX7ULP_MMDC_MAPSR]

	.endm

ENTRY(imx7ulp_suspend)
	push	{r4-r12}

	/*
	 * The value of r0 is mapped the same in origin table and IRAM table,
	 * thus no need to care r0 here.
	 */
	ldr	r1, [r0, #PM_INFO_PBASE_OFFSET]
	ldr	r2, [r0, #PM_INFO_RESUME_ADDR_OFFSET]
	ldr	r3, [r0, #PM_INFO_PM_INFO_SIZE_OFFSET]

	/*
	 * counting the resume address in iram
	 * to set it in SRC register.
	 */
	ldr	r6, =imx7ulp_suspend
	ldr	r7, =resume
	sub	r7, r7, r6
	add	r8, r1, r3
	add	r9, r8, r7

	ldr	r11, [r0, #PM_INFO_PM_INFO_SIM_VBASE_OFFSET]
	/* store physical resume addr and pm_info address. */
	str	r9, [r11, #DGO_GPR3]
	str	r1, [r11, #DGO_GPR4]
	ldr	r7, [r11, #DGO_CTRL0]
	orr	r7, r7, #0xc
	str	r7, [r11, #DGO_CTRL0]
wait_dgo:
	ldr	r7, [r11, #DGO_CTRL0]
	and	r7, r7, #0x18000
	cmp	r7, #0x18000
	bne	wait_dgo

	ldr	r7, [r11, #DGO_CTRL0]
	orr	r7, r7, #0x18000
	bic	r7, r7, #0xc
	str	r7, [r11, #DGO_CTRL0]

	disable_l1_dcache

	store_ttbr1

	ldr	r11, [r0, #PM_INFO_PM_INFO_MMDC_VBASE_OFFSET]

	/*
	 * put DDR explicitly into self-refresh and
	 * disable automatic power savings.
	 */
	ldr	r7, [r11, #MX7ULP_MMDC_MAPSR]
	orr	r7, r7, #0x1
	str	r7, [r11, #MX7ULP_MMDC_MAPSR]

	/* make the DDR explicitly enter self-refresh. */
	ldr	r7, [r11, #MX7ULP_MMDC_MAPSR]
	orr	r7, r7, #(1 << 20)
	str	r7, [r11, #MX7ULP_MMDC_MAPSR]

poll_dvfs_set:
	ldr	r7, [r11, #MX7ULP_MMDC_MAPSR]
	ands	r7, r7, #(1 << 24)
	beq	poll_dvfs_set

	/* put mmdc io into lpm */
	ldr	r11, [r0, #PM_INFO_PM_INFO_MMDC_IO_VBASE_OFFSET]
	ldr	r10, [r0, #PM_INFO_MMDC_IO_NUM_OFFSET]
	ldr	r7, =PM_INFO_MMDC_IO_VAL_OFFSET
	add	r7, r7, r0
mmdc_io_lpm:
	ldr	r8, [r7], #0x8
	mov	r9, #0x0
	str	r9, [r11, r8]
	subs	r10, r10, #0x1
	bne	mmdc_io_lpm

	/* switch NIC clock to FIRC */
	ldr	r10, [r0, #PM_INFO_PM_INFO_SCG1_VBASE_OFFSET]
	ldr	r7, [r10, #SCG_NICCCR]
	bic	r7, #(1 << 28)
	str	r7, [r10, #SCG_NICCCR]

	/* switch RUN clock to FIRC */
	ldr	r7, [r10, #SCG_RCCR]
	bic	r7, #(0xf << 24)
	orr	r7, #(0x3 << 24)
	str	r7, [r10, #SCG_RCCR]

	/* turn off SPLL and SPFD */
	ldr	r7, [r10, #SCG_SPLLPFD]
	mov	r8, r7
	orr	r7, r7, #(0x1 << 31)
	orr	r7, r7, #(0x1 << 23)
	orr	r7, r7, #(0x1 << 15)
	orr	r7, r7, #(0x1 << 7)
	str	r7, [r10, #SCG_SPLLPFD]

	ldr	r7, [r10, #SCG_SPLLCSR]
	bic	r7, r7, #0x1
	str	r7, [r10, #SCG_SPLLCSR]

	/* turn off APLL and APFD */
	ldr	r7, [r10, #SCG_APLLPFD]
	mov	r9, r7
	orr	r7, r7, #(0x1 << 31)
	orr	r7, r7, #(0x1 << 23)
	orr	r7, r7, #(0x1 << 15)
	orr	r7, r7, #(0x1 << 7)
	str	r7, [r10, #SCG_APLLPFD]

	ldr	r7, [r10, #SCG_APLLCSR]
	bic	r7, r7, #0x1
	str	r7, [r10, #SCG_APLLCSR]

	/* Zzz, enter stop mode */
	wfi
	nop
	nop
	nop
	nop

	/* clear core0's entry and parameter */
	ldr	r10, [r0, #PM_INFO_PM_INFO_SIM_VBASE_OFFSET]
	mov	r7, #0x0
	str	r7, [r10, #DGO_GPR3]
	str	r7, [r10, #DGO_GPR4]

	/* enable SPLL and SPFD */
	ldr	r10, [r0, #PM_INFO_PM_INFO_SCG1_VBASE_OFFSET]
	ldr	r7, [r10, #SCG_SPLLCSR]
	orr	r7, r7, #1
	str	r7, [r10, #SCG_SPLLCSR]
wait_spll:
	ldr	r7, [r10, #SCG_SPLLCSR]
	ands	r7, r7, #(1 << 24)
	beq	wait_spll

	str	r8, [r10, #SCG_SPLLPFD]
	/* switch RUN clock to SPLL */
	ldr	r7, [r10, #SCG_RCCR]
	bic	r7, #(0xf << 24)
	orr	r7, #(0x6 << 24)
	str	r7, [r10, #SCG_RCCR]

	/* enable APLL and APFD */
	ldr	r7, [r10, #SCG_APLLCSR]
	orr	r7, r7, #1
	str	r7, [r10, #SCG_APLLCSR]
wait_apll:
	ldr	r7, [r10, #SCG_APLLCSR]
	ands	r7, r7, #(1 << 24)
	beq	wait_apll

	str	r9, [r10, #SCG_APLLPFD]

	/* switch NIC clock to DDR */
	ldr	r7, [r10, #SCG_NICCCR]
	orr	r7, #(1 << 28)
	str	r7, [r10, #SCG_NICCCR]

	/* let mmdc io out of lpm */
	ldr	r11, [r0, #PM_INFO_PM_INFO_MMDC_IO_VBASE_OFFSET]
	ldr	r10, [r0, #PM_INFO_MMDC_IO_NUM_OFFSET]
	ldr	r7, =PM_INFO_MMDC_IO_VAL_OFFSET
	add	r7, r7, r0
mmdc_io_exit_lpm:
	ldr	r8, [r7], #0x4
	ldr	r9, [r7], #0x4
	str	r9, [r11, r8]
	subs	r10, r10, #0x1
	bne	mmdc_io_exit_lpm

	/* let DDR out of self-refresh */
	ldr	r11, [r0, #PM_INFO_PM_INFO_MMDC_VBASE_OFFSET]
	ldr	r7, [r11, #MX7ULP_MMDC_MAPSR]
	bic	r7, r7, #(1 << 20)
	str	r7, [r11, #MX7ULP_MMDC_MAPSR]
poll_dvfs_clear:
	ldr	r7, [r11, #MX7ULP_MMDC_MAPSR]
	ands	r7, r7, #(1 << 24)
	bne	poll_dvfs_clear

	/* enable DDR auto power saving */
	ldr	r7, [r11, #MX7ULP_MMDC_MAPSR]
	bic	r7, r7, #0x1
	str	r7, [r11, #MX7ULP_MMDC_MAPSR]

	restore_ttbr1
	pop	{r4-r12}
	/* return to suspend finish */
	mov	pc, lr

resume:
	/* invalidate L1 I-cache first */
	mov     r6, #0x0
	mcr     p15, 0, r6, c7, c5, 0
	mcr     p15, 0, r6, c7, c5, 6
	/* enable the Icache and branch prediction */
	mov     r6, #0x1800
	mcr     p15, 0, r6, c1, c0, 0
	isb

	ldr	r6, =MX7ULP_SIM_BASE_ADDR
	ldr	r0, [r6, #DGO_GPR4]
	/* get physical resume address from pm_info. */
	ldr	lr, [r0, #PM_INFO_RESUME_ADDR_OFFSET]

	ldr	r11, =MX7ULP_SCG1_BASE_ADDR
	/* enable spll and pfd0 */
	ldr	r5, =PM_INFO_PM_INFO_SCG1_VAL_OFFSET
	add	r6, r5, #48
	ldr	r7, [r0, r6]
	str	r7, [r11, #SCG_SPLLCFG]

	add	r6, r5, #56
	ldr	r7, [r0, r6]
	str	r7, [r11, #SCG_SPLLNUM]

	add	r6, r5, #60
	ldr	r7, [r0, r6]
	str	r7, [r11, #SCG_SPLLDENOM]

	add	r6, r5, #40
	ldr	r7, [r0, r6]
	str	r7, [r11, #SCG_SPLLCSR]
5:
	ldr	r7, [r11, #SCG_SPLLCSR]
	ands	r7, r7, #0x1000000
	beq	5b

	add	r6, r5, #44
	ldr	r7, [r0, r6]
	str	r7, [r11, #SCG_SPLLDIV]

	add	r6, r5, #52
	ldr	r7, [r0, r6]
	str	r7, [r11, #SCG_SPLLPFD]

	add	r6, r5, #0
	ldr	r7, [r0, r6]
	str	r7, [r11, #SCG_RCCR]

	/* enable apll and pfd0 */
	add	r6, r5, #24
	ldr	r7, [r0, r6]
	str	r7, [r11, #SCG_APLLCFG]

	add	r6, r5, #32
	ldr	r7, [r0, r6]
	str	r7, [r11, #SCG_APLLNUM]

	add	r6, r5, #36
	ldr	r7, [r0, r6]
	str	r7, [r11, #SCG_APLLDENOM]

	add	r6, r5, #16
	ldr	r7, [r0, r6]
	str	r7, [r11, #SCG_APLLCSR]
6:
	ldr	r7, [r11, #SCG_APLLCSR]
	ands	r7, r7, #0x1000000
	beq	6b

	add	r6, r5, #20
	ldr	r7, [r0, r6]
	str	r7, [r11, #SCG_APLLDIV]

	add	r6, r5, #28
	ldr	r7, [r0, r6]
	str	r7, [r11, #SCG_APLLPFD]

	/* set ddr ccr */
	add	r6, r5, #4
	ldr	r7, [r0, r6]
	str	r7, [r11, #SCG_DDRCCR]

	/* set nic sel */
	add	r6, r5, #8
	ldr	r7, [r0, r6]
	str	r7, [r11, #SCG_NICCCR]

	/* set firc div2 to get 48MHz */
	add	r6, r5, #12
	ldr	r7, [r0, r6]
	str	r7, [r11, #SCG_FIRCDIV]

	/* restore system OSC div */
	add	r6, r5, #64
	ldr	r7, [r0, r6]
	str	r7, [r11, #SCG_SOSCDIV]

	/* enable mmdc clock in pcc3 */
	ldr	r11, =MX7ULP_PCC3_BASE_ADDR
	ldr	r7, [r11, #0xac]
	orr	r7, r7, #(1 << 30)
	str	r7, [r11, #0xac]

	/* enable GPIO clock in pcc2 */
	ldr	r11, =MX7ULP_PCC2_BASE_ADDR
	ldr	r7, [r11, #0x3c]
	orr	r7, r7, #(1 << 30)
	str	r7, [r11, #0x3c]

	/* restore gpio settings */
	ldr	r10, =MX7ULP_GPIOC_BASE_ADDR
	ldr	r7, =PM_INFO_MX7ULP_GPIO_REG_OFFSET
	add	r7, r7, r0
	ldr	r6, =GPIO_PORT_NUM
12:
	ldr	r9, [r7], #0x4
	str	r9, [r10, #GPIO_PDOR]
	ldr	r9, [r7], #0x4
	str	r9, [r10, #GPIO_PDDR]
	add     r10, r10, #GPIO_PORT_OFFSET
	subs	r6, r6, #0x1
	bne	12b

	/* restore iomuxc settings */
	ldr	r10, =MX7ULP_IOMUXC1_BASE_ADDR
	add	r10, r10, #IOMUX_OFFSET
	ldr	r6, [r0, #PM_INFO_IOMUX_NUM_OFFSET]
	ldr	r7, =PM_INFO_IOMUX_VAL_OFFSET
	add	r7, r7, r0
13:
	ldr	r9, [r7], #0x4
	str	r9, [r10], #0x4
	subs	r6, r6, #0x1
	bne	13b

	/* restore select input settings */
	ldr	r10, =MX7ULP_IOMUXC1_BASE_ADDR
	add	r10, r10, #SELECT_INPUT_OFFSET
	ldr	r6, [r0, #PM_INFO_SELECT_INPUT_NUM_OFFSET]
	ldr	r7, =PM_INFO_SELECT_INPUT_VAL_OFFSET
	add	r7, r7, r0
14:
	ldr	r9, [r7], #0x4
	str	r9, [r10], #0x4
	subs	r6, r6, #0x1
	bne	14b

	/* isoack */
	ldr	r6, =MX7ULP_PMC1_BASE_ADDR
	ldr	r7, [r6, #PMC1_CTRL]
	orr	r7, r7, #(1 << 14)
	str	r7, [r6, #PMC1_CTRL]

	restore_mmdc_settings

	mov	pc, lr
ENDPROC(imx7ulp_suspend)

ENTRY(imx7ulp_cpu_resume)
	bl	v7_invalidate_l1
	b	cpu_resume
ENDPROC(imx7ulp_cpu_resume)
